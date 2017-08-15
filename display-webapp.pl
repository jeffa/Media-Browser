#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use Time::Piece;
use Mojolicious::Lite;
use Data::SpreadPagination;

use lib 'lib';
use MovieUtil qw( get_dbh );

my $DEBUG = shift;

my $PER_PAGE = 10;
my $MAX_PAGE = 6;

my $dbh = get_dbh();

my %valid_fields = map {( $_ => 1 )} qw( sort year genre director writer tag );

get '/' => sub {
    my $self = shift;
    $self->stash( pre => 1, post => 1 );
    $self->render( template => 'index' );
};

get '/input' => sub {
    my $self = shift;
    $self->stash( query => '' );
    $self->render( template => 'input' );
};

get '/select' => sub {
    my $self = shift;
    my $field    = $self->param( 'field' );
    my $selected = $self->param( 'selected' );

    my $query;
    if ($field eq 'genre') {
        $query = 'select genre_id as value, genre_name as label from genres order by label';
    } elsif ($field eq 'director') {
        $query = '
            select p.person_id as value, person_name as label from people p
            inner join role_xref x on x.person_id=p.person_id
            where x.role_id = 1
            order by label
        ';
    } elsif ($field eq 'writer') {
        $query = '
            select p.person_id as value, person_name as label from people p
            inner join role_xref x on x.person_id=p.person_id
            where x.role_id = 2
            order by label
        ';
    } else { #if ($field eq 'tag') {
        $query = 'select tag_id as value, tag as label from tags order by label';
    }

    $self->stash(
        list        => $dbh->selectall_arrayref( $query, {Slice => {}} ),
        selected    => $selected,
        name        => $self->param( 'name' ),
        id          => $self->param( 'id' ),
        class       => $self->param( 'class' ),
        javascript  => $self->param( 'javascript' ),
    );
    $self->render( template => 'select' );
};

get '/tags' => sub {
    my $self = shift;
    my $title_id = int( $self->param( 'title_id' ) || 0 );
    my $edit     = int( $self->param( 'edit' ) || 0 );
    my $new_tags = lc( $self->param( 'tags' ) || '' );
    my @new_tags = split( ' ', $new_tags );

    my @tags = tags( $dbh, $title_id );
    my %old = map { $_ => 1 } @tags;
    my %new = map { $_ => 1 } @new_tags;

    my $sth = $dbh->selectall_arrayref('select tag, tag_id from tags');
    my %all = map { @$_ } @$sth;

    my @to_add = map { $old{$_} ? () : $all{$_} || $_ } keys %new;
    warn "add = @to_add\n";
    my @tag_ids;
    for my $tag (@to_add) {
        if ($tag =~ /\D/) {
            $dbh->do( 'insert into tags(tag) values(?)', undef, $tag );
            push @tag_ids, $dbh->{mysql_insertid};
        } else {
            push @tag_ids, $tag;
        }
    }

    for my $tag_id (@tag_ids) {
        $dbh->do( 'insert into tag_xref(tag_id,title_id) values(?,?)', undef, $tag_id, $title_id );
    }

    my @to_unlink = map { $new{$_} ? () : $all{$_} } keys %old;

    my @to_delete;
    @to_delete = @{ $dbh->selectcol_arrayref( '
        select x.tag_id, count(*) as count
        from tag_xref x 
        inner join tags t on x.tag_id=t.tag_id 
        where x.tag_id in( ' . join(', ', @to_unlink ) . ')
        group by x.tag_id
        having count = 1
    ') } if @to_unlink;

    if (@to_delete) {
        $dbh->do(
            'delete from tags where tag_id in( ' 
            . join(', ', @to_delete ) . ')'
        );
    }

    if (@to_unlink) {
        $dbh->do( 
            'delete from tag_xref where title_id = ? and tag_id in( '
            . join(', ', @to_unlink ) . ')',
            undef, $title_id
        );
    }

    @tags = tags( $dbh, $title_id );
    $self->stash(
        title_id    => $title_id,
        tags        => @tags ? \@tags : [ 'add tags' ],
        joined_tags => join( ' ', @tags ),
    );
    $self->render( template => $edit ? 'edit-tags' : 'show-tags' );
};

get '/fetch' => sub {
    my $self = shift;
    my $curr = int( $self->param( 'curr' ) || 0 ) || 1;
    my $per  = int( $self->param( 'per'  ) || 0 ) || $PER_PAGE;
    my $query = $self->param( 'query' ) || '';
    my $field = $self->param( 'field' ) || '';
    my $sort  = $self->param( 'sort' )  || '';
    my $pre   = $self->param( 'pre' );
    my $post  = $self->param( 'post' );

    $query =~ s/;//g;
    $field = 'sort' unless $valid_fields{$field};

    unless ($dbh->ping) {
        warn "Re-obtaing DB handle\n";
        $dbh = get_dbh();
    }

    my $predicate = '';
    my @vars;
    if ($query) {
        if ($field eq 'sort' or $field eq 'year') {
            $predicate = sprintf ' WHERE %s %s "%s%s%s"', 
                $field,
                ($pre || $post ? 'LIKE' : '='),
                ($pre  ? '%' : ''),
                $query,
                ($post ? '%' : ''),
            ;
        } elsif ($field eq 'genre') {
            if ($query =~ /^\d+$/) {
                $predicate = ' INNER JOIN genre_xref x ON titles.title_id=x.title_id INNER JOIN genres g ON x.genre_id=g.genre_id WHERE g.genre_id = ?';
                push @vars, $query;
            } else {
                $predicate = ' INNER JOIN genre_xref x ON titles.title_id=x.title_id INNER JOIN genres g ON x.genre_id=g.genre_id'
                            . sprintf ' WHERE g.genre_name %s "%s%s%s"', 
                                ($pre || $post ? 'LIKE' : '='),
                                ($pre  ? '%' : ''),
                                $query,
                                ($post ? '%' : ''),
                ;
            }
        } elsif ($field eq 'tag') {
            if ($query =~ /^\d+$/) {
                $predicate = ' INNER JOIN tag_xref x ON titles.title_id=x.title_id INNER JOIN tags t ON x.tag_id=t.tag_id WHERE t.tag_id = ?';
                push @vars, $query;
            } else {
                $predicate = ' INNER JOIN tag_xref x ON titles.title_id=x.title_id INNER JOIN tags t ON x.tag_id=t.tag_id'
                            . sprintf ' WHERE t.tag %s "%s%s%s"', 
                                ($pre || $post ? 'LIKE' : '='),
                                ($pre  ? '%' : ''),
                                $query,
                                ($post ? '%' : ''),
                ;
            }
        } elsif ($field eq 'director') {
            if ($query =~ /^\d+$/) {
                $predicate = ' INNER JOIN role_xref x ON titles.title_id=x.title_id INNER JOIN people p ON x.person_id=p.person_id WHERE x.role_id = 1 and p.person_id = ?';
                push @vars, $query;
            } else {
                $predicate = ' INNER JOIN role_xref x ON titles.title_id=x.title_id INNER JOIN people p ON x.person_id=p.person_id'
                            . sprintf ' WHERE x.role_id = 1 and p.person_name %s "%s%s%s"', 
                                ($pre || $post ? 'LIKE' : '='),
                                ($pre  ? '%' : ''),
                                $query,
                                ($post ? '%' : ''),
                ;
            }
        } elsif ($field eq 'writer') {
            if ($query =~ /^\d+$/) {
                $predicate = ' INNER JOIN role_xref x ON titles.title_id=x.title_id INNER JOIN people p ON x.person_id=p.person_id WHERE x.role_id = 2 and p.person_id = ?';
                push @vars, $query;
            } else {
                $predicate = ' INNER JOIN role_xref x ON titles.title_id=x.title_id INNER JOIN people p ON x.person_id=p.person_id'
                            . sprintf ' WHERE x.role_id = 2 and p.person_name %s "%s%s%s"', 
                                ($pre || $post ? 'LIKE' : '='),
                                ($pre  ? '%' : ''),
                                $query,
                                ($post ? '%' : ''),
                ;
            }
        }
    }

    my $sql = 'SELECT count(*) FROM titles' . $predicate;
    my ($total) = $dbh->selectall_array( $sql, undef, @vars );

    my $pager = Data::SpreadPagination->new({
        totalEntries      => $total->[0],
        currentPage       => $curr,
        entriesPerPage    => $per,
        maxPages          => $MAX_PAGE,
    });

    my $cloud = $dbh->selectall_arrayref('
        select count(*) as total, t.tag, t.tag_id
        from tags t inner join tag_xref x on t.tag_id=x.tag_id
        group by tag
        having total > 2
        order by total desc
    ');
    my %cloud;
    push @{ $cloud{$_->[0]} }, { tag => $_->[1], tag_id => $_->[2] } for @$cloud;

    my @cloud;
    my $last = 999_999_999;
    my $size = 20;
    for my $count (sort { $b <=> $a } keys %cloud) {
        if ($last != $count) {
            $size = $size - .4;
        }

        $_->{size} = $size for @{ $cloud{$count} };
        push @cloud, @{ $cloud{$count} };
        $last = $count;
    }

    @cloud = sort { $a->{tag} cmp $b->{tag} } @cloud;

    unless ($total->[0]) {
        $self->stash(
            titles => [],
            pager  => $pager,
            total  => 0,
            per    => $per,
            pre    => defined($pre)  ? $pre  : 1,
            post   => defined($post) ? $post : 1,
            curr   => $curr,
            sort   => $sort || 'sort',
            query  => $query,
            sql    => $sql,
            field  => $field,
            cloud  => \@cloud,
            DEBUG  => $DEBUG,
        );
        $self->render( template => 'results' );
        return;
    }

    my $order_by = 'sort, year';
    if ($sort eq 'year') {
        $order_by = 'year, sort';
    } elsif ($sort eq 'sortD') {
        $order_by = 'sort DESC, year';
    } elsif ($sort eq 'yearD') {
        $order_by = 'year DESC, sort';
    } elsif ($sort eq 'added') {
        $order_by = 'titles.title_id DESC';
    }

    $sql = sprintf 'SELECT * FROM titles %s ORDER BY %s LIMIT %d,%d', $predicate, $order_by, $pager->first - 1, $per;
    my $titles = $dbh->selectall_arrayref( $sql, {Slice=>{}}, @vars );

    for (@$titles) {

        $_->{files} = 
            $dbh->selectall_arrayref('
                SELECT file_name,
                    display_size as actual_size,
                    duration as actual_duration,
                    ratio as actual_ratio,
                    height, width, frame_rate, source,
                    audio_channels, audio_format, audio_sample_rate
                FROM files
                WHERE title_id = ?
                ORDER BY file_name
            ', {Slice=>{}}, $_->{title_id} )
        ;

        for my $i (0 .. $#{ $_->{files} }) {
            # 01:51:36.960
            my $time = substr( $_->{files}[$i]{actual_duration}, 0, 8 );
            $_->{files}[$i]{actual_duration} = int( Time::Piece->strptime( $time, '%T' )->epoch / 60 ) . ' min';
        }

        $_->{durations} = [
            map $_->[0], $dbh->selectall_array('
                SELECT duration
                FROM durations d
                INNER JOIN titles t ON d.title_id=t.title_id
                WHERE t.title_id = ?
            ', undef, $_->{title_id} )
        ];

        $_->{genres} = 
            $dbh->selectall_arrayref('
                SELECT g.genre_name, g.genre_id
                FROM genres g
                INNER JOIN genre_xref x ON g.genre_id=x.genre_id
                INNER JOIN titles t on x.title_id=t.title_id
                WHERE t.title_id = ?
            ', {Slice=>{}}, $_->{title_id} )
        ;

        $_->{tags} = 
            $dbh->selectall_arrayref('
                SELECT tag, t.tag_id
                FROM tags t
                INNER JOIN tag_xref x ON t.tag_id=x.tag_id
                WHERE x.title_id = ?
            ', {Slice=>{}}, $_->{title_id} )
        ;

        $_->{directors} = 
            $dbh->selectall_arrayref('
                SELECT p.person_name, p.person_id
                FROM people p
                INNER JOIN role_xref x ON p.person_id = x.person_id
                INNER JOIN titles t ON x.title_id = t.title_id
                INNER JOIN roles r ON x.role_id = r.role_id
                WHERE t.title_id = ?
                AND r.role_name = ?
            ', {Slice=>{}}, $_->{title_id}, 'director' )
        ;

        $_->{writers} =
            $dbh->selectall_arrayref('
                SELECT person_name, p.person_id
                FROM people p
                INNER JOIN role_xref x ON p.person_id = x.person_id
                INNER JOIN titles t ON x.title_id = t.title_id
                INNER JOIN roles r ON x.role_id = r.role_id
                WHERE t.title_id = ?
                AND r.role_name = ?
            ', {Slice=>{}}, $_->{title_id}, 'writer' )
        ;
    }

    $self->stash(
        titles => $titles,
        pager  => $pager,
        total  => $total->[0],
        per    => $per,
        pre    => defined($pre)  ? $pre  : 1,
        post   => defined($post) ? $post : 1,
        curr   => $curr,
        sort   => $sort || 'sort',
        query  => $query,
        sql    => $sql,
        field  => $field,
        cloud  => \@cloud,
        DEBUG  => $DEBUG,
    );

    $self->respond_to(
      json => { json => { titles => $titles } },
      xml  => sub { $self->render( template => 'results' ) },
      txt  => sub { $self->render( template => 'results' ) },
      html => sub { $self->render( template => 'results' ) },
    );
};

app->start( daemon => '-l', 'http://*:3000' );

sub tags {
    my ($dbh, $title_id) = @_;
    @{ $dbh->selectcol_arrayref('
        select t.tag
        from tags t
        inner join tag_xref x
        on t.tag_id=x.tag_id
        where x.title_id = ?
        order by t.tag
    ', undef, $title_id ) }
}


__DATA__
@@ index.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title>Movie Collection Browser</title>
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" />
    <style type="text/css">
        a   { color: #333 }
        body {
           transform: scale(0.9);
           transform-origin: 0 0;
        }
    </style>
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.12.4/jquery.min.js"></script>
    <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>
    <script type="text/javascript">

        function load() {
            $(document).keydown(function(e) {
                switch(e.which) {
                    case 13: fetch_results();   break;
                    case 37: step_left();       break;
                    case 38: step_up();         break;
                    case 39: step_right();      break;
                    case 40: step_down();       break;
                    default: return;
                }
                e.preventDefault();
            });

            _ajaxGET( '/fetch', '#results' );
        }

        function _ajaxGET( url, id, err ) {

            if (!err) {
                err = '<div class="alert alert-danger">'
                    + '<button type="button" class="close" data-dismiss="alert">&times;</button>'
                    + '<strong>Error!</strong>'
                    + ' Ajax call failed: ' 
                    + url 
                    + '</div>'
            }

            console.log( url );
            var $btn = $( '#go' ).button( 'loading' );
            $.ajax( {
                url: url,
                type: 'GET',
                success: function( data, status, xhr ) {
                    $( id ).html( xhr.responseText );
                    $btn.button( 'reset' );
                },
                error: function( xhr, status, error ) {
                    $( id ).html( err );
                }
            });
        }

    </script>
  </head>
  <body onload="javascript: load()">
    <div id="results"></div>
  </body>
</html>

@@ results.html.ep
%= include 'javascript', titles => $titles, pager => $pager

<div class="container-fluid">
    <div class="row">
        <div id="content" class="col-md-7">
            <table width="100%"><tr><td valign="top">
                %= include 'search-stats', total => $total, curr => $curr, per => $per
            </td><td valign="top" align="right">
                %= include 'pagination', pager => $pager
            </td></tr></table>

            <div class="panel-group" id="accordion" role="tablist" aria-multiselectable="false">
            <% for my $i (0 .. $#$titles) { %>
                %= include 'title', obj => $titles->[$i], i => $i, DEBUG => $DEBUG
            <% } %>
            </div>
        </div>

        <div class="col-md-5">
        <br />
        %= include 'form',          query => $query, field => $field, pre => $pre, post => $post, per => $per, 'sort' => $sort
        %= include 'sort-links',    'sort' => $sort
        %= include 'year-links',    query => $query, list => [ [19,20], [19,30], [19,40], [19,50], [19,60], [19,70], [19,80], [19,90], [20,'00'], [20,10] ]
        %= include 'alpha-links',   query => $query, list => [ 'a' .. 'z' ]
        %= include 'per-page',      per => $per, list => [ 10,25,50,100,250,500 ]
        %= include 'tag-cloud',     cloud => $cloud, query => $query
        </div>
    </div>
</div>

@@ title.html.ep
<div class="panel panel-default">
    <div class="panel-heading" role="tab" id="heading-<%= $obj->{title_id} %>">

        <h6 class="panel-title">
        <a onclick="javascript: step_here(<%= $i %>)" role="button" data-toggle="collapse" data-parent="#accordion" href="#collapse-<%= $obj->{title_id} %>" aria-expanded="<%= $i ? 'true' : 'false' %>" <%= $i ? 'class="collapsed"' : '' %> aria-controls="collapse-<%= $obj->{title_id} %>">
            <%= $obj->{title} %> (<%= $obj->{year} %>)
        </a>
        </h6>

    </div>
    <div id="collapse-<%= $obj->{title_id} %>" class="panel-collapse collapse <%= $i ? '' : 'in' %>" role="tabpanel" aria-labelledby="heading-<%= $obj->{title_id} %>">
        <div class="panel-body">

            <table width="100%"><tr><td valign="top">
                %= include 'title-details', obj => $obj, DEBUG => $DEBUG
            </td><td width="30%" align="right" valign="top">
                %= include 'voting', obj => $obj
                <div><img class="img-thumbnail" src="<%= $obj->{cover} %>" /></div>
            </td></tr></table>

        </div>
    </div>
</div>

@@ title-details.html.ep
<table class="table-striped details">
  <tr>
    <th><span class="glyphicon glyphicon-film alert-success" aria-hidden="true" data-toggle="tooltip" title="IMDB ID"></span></th>
    <td><span class="badge alert-success"><%= link_to $obj->{imdb_id} => "http://www.imdb.com/title/$obj->{imdb_id}", target => '_blank' %></span></td>
  </tr>
  <tr>
    <th><span class="glyphicon glyphicon-calendar" aria-hidden="true" data-toggle="tooltip" title="Year"></span></th>
    <td><span class="badge alert-success"><%= link_to $obj->{year} => "javascript: by_link( 'year', '$obj->{year}' )" %></span></td>
  </tr>
  <tr>
    <th><span class="glyphicon glyphicon-bullhorn" aria-hidden="true" data-toggle="tooltip" title="Director"></span></th>
    <td>
    <% for (@{$obj->{directors} || []}) { %>
        <span class="badge alert-success"><%= link_to $_->{person_name} => "javascript: by_link( 'director', '$_->{person_id}' )" %></span>
    <% } %>
    </td>
  </tr>
  <tr>
    <th><span class="glyphicon glyphicon-pencil" aria-hidden="true" data-toggle="tooltip" title="Writer"></span></th>
    <td>
    <% for (@{$obj->{writers} || []}) { %>
        <span class="badge alert-success"><%= link_to $_->{person_name} => "javascript: by_link( 'writer', '$_->{person_id}' )" %></span>
    <% } %>
    </td>
  </tr>
  <tr>
    <th><span class="glyphicon glyphicon-list-alt" aria-hidden="true" data-toggle="tooltip" title="Genres"></span></th>
    <td>
    <% for (sort { $a->{genre_name} cmp $b->{genre_name} } @{$obj->{genres} || []}) { %>
        <span class="badge alert-success"><%= link_to ucfirst($_->{genre_name}) => "javascript: by_link( 'genre', '$_->{genre_id}' )" %></span>
    <% } %>
    </td>
  </tr>
  <tr>
    <th><span class="glyphicon glyphicon-tags" aria-hidden="true" data-toggle="tooltip" title="Tags"></span></th>
    <td>
        <div id="tag-<%= $obj->{title_id} %>" width="100%">
        <% for (@{$obj->{tags}}) { %>
          <% if ($DEBUG) { %>
            <span class="badge alert-success" onclick="javascript: edit_tag( <%= $obj->{title_id} %>, '<%= join( ' ', map $_->{tag}, @{$obj->{tags}} ) %>' )">
                <%= $_->{tag} %> <span class="glyphicon glyphicon-plus-sign" aria-hidden="true"></span>
            </span>
          <% } else { %>
            <span class="badge alert-success"><%= link_to $_->{tag} => "javascript: by_link( 'tag', '$_->{tag_id}' )" %></span>
          <% } %>
        <% } %>
        <% unless (@{ $obj->{tags} || {} }) { %>
          <% if ($DEBUG) { %>
            <span class="badge alert-success" onclick="javascript: edit_tag( <%= $obj->{title_id} %>, '' )">
                add tags <span class="glyphicon glyphicon-plus-sign" aria-hidden="true"></span>
            </span>
          <% } %>
        <% } %>
        </div>
    </td>
  </tr>
  <% if ($DEBUG) { %>
  <tr>
    <th><span class="glyphicon glyphicon-briefcase" aria-hidden="true" data-toggle="tooltip" title="Story"></span></th>
    <td><span style="font-size: x-small"><%== $obj->{story} %></span></td>
  </tr>
  <% } %>
  <tr>
    <td>&nbsp;</td>
    <td align="center">
      <% if ($obj->{ratio}) { %>
        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-picture" aria-hidden="true" data-toggle="tooltip" title="Aspect Ratio"></span>
            <%= $obj->{ratio} %>
        </span>
      <% } %>
      <% for (@{$obj->{durations} || []}) { %>
        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-hourglass" aria-hidden="true" data-toggle="tooltip" title="Durations"></span>
            <%= $_ %>
        </span>
      <% } %>
    </td>
  </tr>

%= include 'files', files => $obj->{files} || []

</table>

@@ files.html.ep
<% for (@$files) { %>
  <% my $f = $_->{file_name}; %>
  <% my $s = substr( $f, 0, 60 ); %>
  <tr>
    <th><span class="glyphicon glyphicon-folder-open alert-warning" aria-hidden="true" data-toggle="tooltip" title="File"></span></th>
    <td><span class="badge alert-warning"><% if ($f eq $s) { %><%= $f %><% } else { %><abbr title="<%= $f %>"><%= $s %></abbr><% } %></span></td>
  </tr>
  <tr>
    <td>&nbsp;</td>
    <td align="center">
        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-picture" aria-hidden="true" data-toggle="tooltip" title="Actual Ratio"></span>
            <%= $_->{actual_ratio} %>
        </span>

        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-hourglass" aria-hidden="true" data-toggle="tooltip" title="Actual Duration"></span>
            <%= $_->{actual_duration} %>
        </span>

        <br />

        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-fullscreen" aria-hidden="true" data-toggle="tooltip" title="Dimension"></span>
            <%= join 'x', $_->{width}, $_->{height} %>
        </span>

        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-file" aria-hidden="true" data-toggle="tooltip" title="Actual Size"></span>
            <%= $_->{actual_size} %>
        </span>

        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-cd" aria-hidden="true" data-toggle="tooltip" title="Frame Rate"></span>
            <%= $_->{frame_rate} %>
        </span>

        <br />

        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-tasks" aria-hidden="true" data-toggle="tooltip" title="Audio Channels"></span>
            <%= $_->{audio_channels} %>
        </span>

        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-floppy-disk" aria-hidden="true" data-toggle="tooltip" title="Audio Format"></span>
            <%= $_->{audio_format} %>
        </span>

        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-headphones" aria-hidden="true" data-toggle="tooltip" title="Audio Sample Rate"></span>
            <%= $_->{audio_sample_rate} %>
        </span>

        <% if ($_->{source}) { %>
        <br />
        <span class="badge alert-warning">
            <span class="glyphicon glyphicon-user" aria-hidden="true" data-toggle="tooltip" title="Source"></span>
            <%= (split( /\./, $_->{source}, 2 ))[0] %>
        </span>
        <% } %>
    </td>
  </tr>
<% } %>

@@ voting.html.ep
<div align="center" class="btn-group" data-toggle="buttons">
  <label id="thumbs-up-<%= $obj->{title_id} %>" onclick="javascript: thumbs( 'up', <%= $obj->{title_id} %> )" class="btn btn-link'">
    <input type="checkbox" />
    <span float="right" class="glyphicon glyphicon-thumbs-up" aria-hidden="true"></span> &nbsp;
  </label>
</div>

<div align="center" class="btn-group" data-toggle="buttons">
  <label id="thumbs-down-<%= $obj->{title_id} %>" onclick="javascript: thumbs( 'down', <%= $obj->{title_id} %> )" class="btn btn-link'">
    <input type="checkbox" />
    <span float="right" class="glyphicon glyphicon-thumbs-down" aria-hidden="true"></span>
  </label>
</div>

@@ search-stats.html.ep
<h2>
  <% if ($total) { %>
    <span class="glyphicon glyphicon-eye-open" aria-hidden="true" data-toggle="tooltip" title="<%= $total %> titles found"></span>
    <%= $total %> <small>(<%= $curr * $per - ($per - 1) %> - <%= $curr * $per %>)</small>
  <% } else { %>
    <span class="glyphicon glyphicon-eye-close" aria-hidden="true" data-toggle="tooltip" title="No titles found :("></span>
  <% } %>
</h2>

@@ pagination.html.ep
<nav aria-label="Page navigation">
    <ul class="pagination">
        <li class="<%= $pager->previous_page ? '' : 'disabled' %>" aria-label="Previous">
            <a href="javascript: step_left();">&laquo;</a>
        </li>
    <% for my $number ($pager->pages_in_spread) { %>
        <% if ($number) { %>
        <li class="<%= $pager->current_page == $number ? 'active' : '' %>">
            <a href="javascript: fetch_results( <%= $number %> );"><%= $number %></a>
        </li>
        <% } else { %>
        <li class="disabled"><a href="javascript:void">...</a></li>
        <% } %>
    <% } %>
        <li class="<%= $pager->next_page ? '' : 'disabled' %>" aria-label="Next">
            <a href="javascript: step_right();">&raquo;</a>
        </li>
    </ul>
</nav>

@@ form.html.ep
<form class="form-inline" action="javascript: void(0);" id="search" name="search" class="navbar-search">

    <button class="btn btn-primary" type="button" onclick="javascript: reset_form()">
        <span float="right" class="glyphicon glyphicon-home" aria-hidden="true"></span>
    </button>

    <%= include select =>
        name        => 'field',
        id          => 'field',
        class       => 'form-control',
        selected    => $field,
        javascript  => qq|onchange="javascript: change_query( this, 'query', '$query' )"|,
        list        => [
            { value => 'sort',      label => 'Title' },
            { value => 'year',      label => 'Year' },
            { value => 'genre',     label => 'Genre' },
            { value => 'director',  label => 'Director' },
            { value => 'writer',    label => 'Writer' },
            { value => 'tag',       label => 'Tag' },
        ],
    %>

    <div class="btn-group" data-toggle="buttons">
      <label id="pre-button" onclick="javascript: toggle('pre')" class="btn <%= $pre ? 'btn-info active' : 'btn-link' %>">
        <input type="checkbox" />%
      </label>
    </div>

    <span id="querybox"><%= include input => query => $query %></span>

    <div class="btn-group" data-toggle="buttons">
      <label id="post-button" onclick="javascript: toggle('post')" class="btn <%= $post ? 'btn-info active' : 'btn-link' %>">
        <input type="checkbox" />%
      </label>
    </div>

    <button id="go" class="btn btn-primary" type="button" onclick="javascript: fetch_results()" data-loading-text="...">
        <span float="right" class="glyphicon glyphicon-search" aria-hidden="true"></span>
    </button>

    <input id="curr" name="curr" type="hidden" value="<%= $curr %>" />
    <input id="pre"  name="pre"  type="hidden" value="<%= $pre %>" />
    <input id="post" name="post" type="hidden" value="<%= $post %>" />
    <input id="per"  name="per"  type="hidden" value="<%= $per %>" />
    <input id="sort" name="sort" type="hidden" value="<%= $sort %>" />

</form>

@@ edit-tags.html.ep
<input id="edit-tag-<%= $title_id %>" type="text" value="<%= $joined_tags %>" onblur="javascript: show_tag( '<%= $title_id %>', this )" />

@@ show-tags.html.ep
<% for my $tag (@$tags) { %>
    <span class="badge alert-success" onclick="javascript: edit_tag( '<%= $title_id %>', '<%= $joined_tags %>' )">
        <%= $tag %>
        <span class="glyphicon glyphicon-plus-sign" aria-hidden="true"></span>
    </span>
<% } %>

@@ input.html.ep
<input name="query" class="form-control" type="text" placeholder="ALL" value="<%= $query %>" />

@@ select.html.ep
<select
    <% if ($name) { %>name="<%= $name %>"<% } %>
    <% if ($id) { %>id="<%= $id %>"<% } %>
    <% if ($class) { %>class="<%= $class %>"<% } %>
    <% if ($javascript) { %><%== $javascript %><% } %>
>
<% for my $item (@$list) { %>
    <option value="<%= $item->{value} %>" <%= $item->{value} eq $selected ? 'selected="1"' : '' %>>
        <%= $item->{label} %>
    </option>
<% } %>
</select>

@@ per-page.html.ep
<table width="100%"><tr><td>
    <nav aria-label="Sort navigation">
      <ul class="pagination">
        <li class="disabled"><a>Per Page:</a></li>
        <% for my $number (@$list) { %>
          <li class="<%= $number == $per ? 'active' : '' %>">
              <a href="javascript: set_results_per( <%= $number %> );"><%= $number %></a>
        </li>
        <% } %>
      </ul>
    </nav>
</td><td align="right">
    <nav aria-label="Data format">
      <ul class="pagination">
        <li><a href="javascript: format( 'xml' );">xml</a></li>
        <li><a href="javascript: format( 'json' );">json</a></li>
      </ul>
    </nav>
</td></tr></table>

@@ sort-links.html.ep
<nav aria-label="Sort navigation">
  <ul class="pagination">
     <li class="disabled"><a>Title</a></li>
     <li class="<%= $sort eq 'sort' ? 'active' : '' %>">
          <a href="javascript: sort_by( 'sort' );"><span class="glyphicon glyphicon-sort-by-attributes" aria-hidden="true"></a>
     </li>
     <li class="<%= $sort eq 'sortD' ? 'active' : '' %>">
          <a href="javascript: sort_by( 'sortD' );"><span class="glyphicon glyphicon-sort-by-attributes-alt" aria-hidden="true"></a>
     </li>
  </ul>
  <ul class="pagination">
     <li class="disabled"><a>Year</a></li>
     <li class="<%= $sort eq 'year' ? 'active' : '' %>">
          <a href="javascript: sort_by( 'year' );"><span class="glyphicon glyphicon-sort-by-attributes" aria-hidden="true"></a>
     </li>
     <li class="<%= $sort eq 'yearD' ? 'active' : '' %>">
          <a href="javascript: sort_by( 'yearD' );"><span class="glyphicon glyphicon-sort-by-attributes-alt" aria-hidden="true"></a>
     </li>
  </ul>
  <ul class="pagination">
     <li class="disabled"><a>Added</a></li>
     <li class="<%= $sort eq 'added' ? 'active' : '' %>">
          <a href="javascript: sort_by( 'added' );"><span class="glyphicon glyphicon-sort-by-attributes-alt" aria-hidden="true"></a>
     </li>
  </ul>
</nav>

@@ year-links.html.ep
<div>
<% for (@$list) { %>
    <% my $year = join '', @$_; chop $year; %>
    <div class="btn-group" data-toggle="buttons">
      <label id="pre-button" style="font-size: 8pt" onclick="javascript: by_link( 'year', '<%= $year %>', 0, 1, 'year' )" class="btn <%= $query eq $year ? 'btn-info active' : 'btn-link' %>">
        <%= $_->[1] . "s" %>
      </label>
    </div>
<% } %>
</div>

@@ alpha-links.html.ep
<div>
<% for (@$list) { %>
    <div class="btn-group" data-toggle="buttons">
      <label id="pre-button" style="font-size: 9pt" onclick="javascript: by_link( 'sort', '<%= $_ %>', 0, 1 )" class="btn <%= $query eq $_ ? 'btn-info active' : 'btn-link' %>">
        <%= $_ %>
      </label>
    </div>
<% } %>
</div>

@@ tag-cloud.html.ep
<div class="jumbotron">
  <% for my $tag (@$cloud) { %>
    <% next if $tag->{size} < 8; %>
    <% if ($query eq $tag->{tag_id}) { %>
        <u style="<%= sprintf('font-size: %dpt', $tag->{size}) %>"><%= $tag->{tag} %></u>
    <% } else { %>
        <%= link_to $tag->{tag} => "javascript: by_link( 'tag', '$tag->{tag_id}' )", style => sprintf('font-size: %dpt', $tag->{size}) %>
    <% } %>
  <% } %>
</div>

@@ javascript.html.ep
<script type="text/javascript">
var panes = [ <%= join( ', ', map $_->{title_id}, @$titles ) %> ];
var curr  = 0;

function fetch_results( curr = 1 ) {
    var params = $.param([
        {name: "curr",      value: curr},
        {name: "field",     value: document.search.field.value},
        {name: "query",     value: document.search.query.value},
        {name: "per",       value: document.search.per.value},
        {name: "pre",       value: document.search.pre.value},
        {name: "post",      value: document.search.post.value},
        {name: "sort",      value: document.search.sort.value}
    ]);

    var url  = '/fetch?' + params;
    _ajaxGET( url, '#results' );
}

function reset_form() {
    document.search.per.value   = 10;
    document.search.pre.value   = 1;
    document.search.post.value  = 1;
    document.search.field.value = 'sort';
    document.search.sort.value  = 'sort';
    document.search.query.value = '';
    fetch_results();
}

function set_results_per( per ) {
    document.search.per.value = per;
    fetch_results();
}

function toggle( param ) {
    var value = $( '#' + param ).val();
    $( '#' + param ).val( value > 0 ? 0 : 1 );
    var value = $( '#' + param ).val();
    $( '#' + param + '-view' ).val( value );
    $( '#' + param + '-button' ).toggleClass( 'btn-info' );
    $( '#' + param + '-button' ).toggleClass( 'btn-link' );
}

function thumbs( param, title_id ) {
    $( '#thumbs-' + param + '-' + title_id ).toggleClass( 'btn-danger' );
}

function step_left() {
    if (<%= $pager->previous_page ? 1 : 0 %>) {
        fetch_results( <%= $pager->previous_page %> );
    }
}

function step_right() {
    if (<%= $pager->next_page ? 1 : 0 %>) {
        fetch_results( <%= $pager->next_page %> );
    }
}

function step_up() {
    $( '.panel-collapse' ).collapse( 'hide' );
    if (curr < 0) return;
    $( '#collapse-' + panes[--curr] ).collapse( 'show' );
}

function step_down() {
    $( '.panel-collapse' ).collapse( 'hide' );
    if (curr > <%= $#$titles %>) return;
    $( '#collapse-' + panes[++curr] ).collapse( 'show' );
}

function step_here( new_curr ) {
    if (new_curr > <%= $#$titles %>) return;
    if (new_curr < 0) return;
    $( '.panel-collapse' ).collapse( 'hide' );
    curr = new_curr;
}

function sort_by( field ) {
    document.search.sort.value = field;
    fetch_results();
}

function by_link( field, value, pre = 0, post = 0, sort = 'sort' ) {
    document.search.field.value = field;
    document.search.query.value = value;
    document.search.pre.value   = pre;
    document.search.post.value  = post;
    document.search.sort.value  = sort;
    fetch_results();
}

function format( format ) {

    var params = $.param([
        {name: "field",     value: document.search.field.value},
        {name: "query",     value: document.search.query.value},
        {name: "sort",      value: document.search.sort.value},
        {name: "pre",       value: document.search.pre.value},
        {name: "post",      value: document.search.post.value},
        {name: "per",       value: document.search.per.value},
        {name: "curr",      value: document.search.curr.value},
    ]);

    var url = '/fetch.' + format + '?' + params;
    window.location.href = url;
}

function edit_tag( title_id, tags ) {
    var params = $.param([
        {name: "title_id",  value: title_id},
        {name: "tags",      value: tags},
        {name: "edit",      value: 1}
    ]);

    var url  = '/tags?' + params;
    _ajaxGET( url, '#tag-' + title_id );
    //$( '#edit-tag-' + title_id ).focus();
}

function show_tag( title_id, input ) {
    var params = $.param([
        {name: "title_id",  value: title_id},
        {name: "tags",      value: input.value},
    ]);

    var url  = '/tags?' + params;
    _ajaxGET( url, '#tag-' + title_id );
}

function change_query( select, name, selected ) {

    if (select.value == 'genre' || select.value == 'tag') {
        var params = $.param([
            {name: "field",     value: select.value},
            {name: "name",      value: name},
            {name: "class",     value: "form-control"},
            {name: "selected",  value: selected},
        ]);
        _ajaxGET( '/select?' + params, '#querybox' );
    } else {
        _ajaxGET( '/input', '#querybox' );
    }
}
</script>

@@ results.xml.ep
<?xml version="1.0" encoding="UTF-8"?>
<titles>
<% for my $title (@$titles) { %>
    <title>
        <title><%= $title->{title} %></title>
        <imdb_id><%= $title->{imdb_id} %></imdb_id>
        <year><%= $title->{year} %></year>
        <cover><%= $title->{cover} %></cover>
        <tagline><%= $title->{tagline} %></tagline>
        <story><%= $title->{story} %></story>
        <directors>
        <% for (@{$title->{directors} || []}) { %>
            <director>
                <id><%= $_->{person_id} %></id>
                <name><%= $_->{person_name} %></name>
            </director>
        <% } %>
        </directors>
        <writers>
        <% for (@{$title->{writers} || []}) { %>
            <writer>
                <id><%= $_->{person_id} %></id>
                <name><%= $_->{person_name} %></name>
            </writer>
        <% } %>
        </writers>
        <genres>
        <% for (@{$title->{genres} || []}) { %>
            <genre>
                <id><%= $_->{genre_id} %></id>
                <name><%= $_->{genre_name} %></name>
            </genre>
        <% } %>
        </genres>
        <tags>
        <% for (@{$title->{tags} || []}) { %>
            <tag>
                <id><%= $_->{tag} %></id>
                <name><%= $_->{tag_id} %></name>
            </tag>
        <% } %>
        </tags>
        <files>
        <% for (@{$title->{files} || []}) { %>
            <file>
                <filename><%= $_->{file_name} %></filename>
                <ratio><%= $_->{actual_ratio} %></ratio>
                <duration><%= $_->{actual_duration} %></duration>
                <width><%= $_->{width} %></width>
                <height><%= $_->{height} %></height>
                <size><%= $_->{actual_size} %></size>
                <frame_rate><%= $_->{frame_rate} %></frame_rate>
                <audio_channels><%= $_->{audio_channels} %></audio_channels>
                <audio_format><%= $_->{audio_format} %></audio_format>
                <audio_sample_rate><%= $_->{audio_sample_rate} %></audio_sample_rate>
                <source><%= $_->{source} %></source>
            </file>
        <% } %>
        </files>
    </title>
<% } %>
</titles>

@@ results.txt.ep
<% for my $title (@$titles) { =%>
title="<%== $title->{title} %>" id=<%= $title->{imdb_id} %> year=<%= $title->{year} %> cover=<%= $title->{cover} %>
<% } =%>
