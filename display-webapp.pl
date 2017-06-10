#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use Mojolicious::Lite;
use Data::SpreadPagination;

use lib 'lib';
use MovieUtil qw( get_dbh );

my $PER_PAGE = 25;
my $MAX_PAGE = 10;

my $dbh = get_dbh();

my %valid_fields = map {( $_ => 1 )} qw( sort year genre person );

get '/' => sub {
    my $self = shift;
    $self->stash( per => $PER_PAGE );
    $self->render( template => 'index' );
};

get '/fetch' => sub {
    my $self = shift;
    my $curr = int( $self->param( 'curr' ) ) || 1;
    my $per  = int( $self->param( 'per'  ) ) || $PER_PAGE;
    my $query = $self->param( 'query' );
    my $field = $self->param( 'field' );
    my $pre   = $self->param( 'pre' );
    my $post  = $self->param( 'post' );
    my $sort  = $self->param( 'sort' );

    $field = 'sort' unless $valid_fields{$field};
    warn "field = $field\n";

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
        } elsif ($field eq 'person') {
            if ($query =~ /^\d+$/) {
                $predicate = ' INNER JOIN role_xref x ON titles.title_id=x.title_id INNER JOIN people p ON x.person_id=p.person_id WHERE p.person_id = ?';
                push @vars, $query;
            } else {
                $predicate = ' INNER JOIN role_xref x ON titles.title_id=x.title_id INNER JOIN people p ON x.person_id=p.person_id'
                            . sprintf ' WHERE p.person_name %s "%s%s%s"', 
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

    unless ($total->[0]) {
        $self->stash( titles => [], pager => $pager, total => 'No', per => $per, curr => $curr );
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
    }

    $sql = sprintf 'SELECT * FROM titles %s ORDER BY %s LIMIT %d,%d', $predicate, $order_by, $pager->first - 1, $per;
    warn "$sql\n";
    my $titles = $dbh->selectall_arrayref( $sql, {Slice=>{}}, @vars );

    for (@$titles) {

        $_->{files} = 
            $dbh->selectall_arrayref('
                SELECT file_name,
                    display_size as actual_size,
                    duration as actual_duration,
                    ratio as actual_ratio,
                    height, width, frame_rate
                FROM files
                WHERE title_id = ?
            ', {Slice=>{}}, $_->{title_id} )
        ;

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
        total  => $total->[0] || 'No',
        per    => $per,
        curr   => $curr,
        sort   => $sort,
    );

    $self->render( template => 'results' );
};

app->start( daemon => '-l', 'http://*:3000' );



__DATA__
@@ index.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title>Movie Collection Browser</title>
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" />
    <style type="text/css">
        table.details { padding: 10; }
        table.details th { width: 15%; vertical-align: top; }
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

            fetch_results();
        }

        function set_results_per( per ) {
            document.search.per.value = per;
            fetch_results();
        }

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
    <div class="container-fluid">
      <div class="row">
        <div id="content" class="col-md-7">
            <div id="results"></div>
        </div>
        <div class="col-md-5">
            <br />
            <form class="form-inline" action="javascript: void(0);" id="search" name="search" class="navbar-search">

                <select name="field" class="form-control">
                  <option value="sort">Title</option>
                  <option value="year">Year</option>
                  <option value="genre">Genre</option>
                  <option value="person">Person</option>
                </select>

                <div class="btn-group" data-toggle="buttons">
                  <label onclick="javascript: toggle('pre')" class="btn btn-info active"><input type="checkbox" checked="1" />%</label>
                </div>

                <input name="query" id="appendedInputButton" class="form-control" type="text" placeholder="ALL" />

                <div class="btn-group" data-toggle="buttons">
                  <label onclick="javascript: toggle('post')" class="btn btn-info active"><input type="checkbox" checked="1" />%</label>
                </div>

                <button id="go" class="btn btn-primary" type="button" onclick="javascript: fetch_results()" data-loading-text="Loading..."> Search! </button>

                <input id="curr" name="curr" type="hidden" />
                <input id="per"  name="per"  type="hidden" value="<%= $per %>" />
                <input id="pre"  name="pre"  type="hidden" value="1" />
                <input id="post" name="post" type="hidden" value="1" />
                <input id="sort" name="sort" type="hidden" value="sort" />

            </form>

        </div>
      </div>
    </div>
  </body>
</html>

@@ results.html.ep
<script type="text/javascript">
var panes = [ <%= join( ', ', map $_->{title_id}, @$titles ) %> ];
var curr  = 0;

function toggle( param ) {
    var value = $( '#' + param ).val();
    $( '#' + param ).val( value > 0 ? 0 : 1 );
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
    if (curr < 1) return;
    curr--;
    $( '#collapse-' + panes[curr+1] ).collapse( 'hide' );
    $( '#collapse-' + panes[curr] ).collapse( 'show' );
}

function step_down() {
    if (curr >= <%= $#$titles %>) return;
    curr++;
    $( '#collapse-' + panes[curr-1] ).collapse( 'hide' );
    $( '#collapse-' + panes[curr] ).collapse( 'show' );
}

function sort_by( field ) {
    document.search.sort.value = field;
    fetch_results();
}

function by_link( field, value ) {
    document.search.pre.value = 0;
    document.search.post.value = 0;
    document.search.field.value = field;
    document.search.query.value = value;
    fetch_results();
}
</script>

<h2><%= $total %> titles found (<%= $curr * $per - ($per - 1) %> - <%= $curr * $per %>)</h2>

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

<table width="100%"><tr><td>
    <nav aria-label="Sort navigation">
      <ul class="pagination">
         <li class="disabled"><a>Sort:</a></li>
         <li class="<%= $sort eq 'sort' ? 'active' : '' %>">
              <a href="javascript: sort_by( 'sort' );">Title &#x25B2;</a>
         </li>
         <li class="<%= $sort eq 'sortD' ? 'active' : '' %>">
              <a href="javascript: sort_by( 'sortD' );">Title &#x25BC;</a>
         </li>
         <li class="<%= $sort eq 'year' ? 'active' : '' %>">
              <a href="javascript: sort_by( 'year' );">Year &#x25B2;</a>
         </li>
         <li class="<%= $sort eq 'yearD' ? 'active' : '' %>">
              <a href="javascript: sort_by( 'yearD' );">Year &#x25BC;</a>
         </li>
      </ul>
    </nav>

</td><td align="right">

    <nav aria-label="Per navigation">
      <ul class="pagination">
          <li class="disabled"><a>Per:</a></li>
        <% for my $number (10,25,50,100,200) { %>
          <li class="<%= $number == $per ? 'active' : '' %>">
              <a href="javascript: set_results_per( <%= $number %> );"><%= $number %></a>
          </li>
        <% } %>
      </ul>
    </nav>

</td></tr></table>

<div class="panel-group" id="accordion" role="tablist" aria-multiselectable="false">
<% for my $i (0 .. $#$titles) { %>
  <% my $obj = $titles->[$i]; %>
  <div class="panel panel-default">
    <div class="panel-heading" role="tab" id="heading-<%= $obj->{title_id} %>">
      <h6 class="panel-title">
        <a role="button" data-toggle="collapse" data-parent="#accordion" href="#collapse-<%= $obj->{title_id} %>" aria-expanded="<%= $i ? 'true' : 'false' %>" <%= $i ? 'class="collapsed"' : '' %> aria-controls="collapse-<%= $obj->{title_id} %>">
            <%= $obj->{title} %> (<%= $obj->{year} %>)
        </a>
      </h4>
    </div>
    <div id="collapse-<%= $obj->{title_id} %>" class="panel-collapse collapse <%= $i ? '' : 'in' %>" role="tabpanel" aria-labelledby="heading-<%= $obj->{title_id} %>">
      <div class="panel-body">

        <table width="100%"><tr><td valign="top">
            <table class="table-striped details">
              <tr>
                <th>IMDB ID</th>
                <td><span class="badge alert-success"><%= link_to $obj->{imdb_id} => "http://www.imdb.com/title/$obj->{imdb_id}", target => '_blank' %></span></td>
              </tr>
              <tr>
                <th>Year</th>
                <td><span class="badge alert-success"><%= link_to $obj->{year} => "javascript: by_link( 'year', '$obj->{year}' )" %></span></td>
              </tr>
              <tr>
                <th>Director</th>
                <td>
                <% for (@{$obj->{directors} || []}) { %>
                    <span class="badge alert-success"><%= link_to $_->{person_name} => "javascript: by_link( 'person', '$_->{person_id}' )" %></span>
                <% } %>
                </td>
              </tr>
              <tr>
                <th>Writer</th>
                <td>
                <% for (@{$obj->{writers} || []}) { %>
                    <span class="badge alert-success"><%= link_to $_->{person_name} => "javascript: by_link( 'person', '$_->{person_id}' )" %></span>
                <% } %>
                </td>
              </tr>
              <tr>
                <th>Genre</th>
                <td>
                <% for (sort { $a->{genre_name} cmp $b->{genre_name} } @{$obj->{genres} || []}) { %>
                    <span class="badge alert-success"><%= link_to ucfirst($_->{genre_name}) => "javascript: by_link( 'genre', '$_->{genre_id}' )" %></span>
                <% } %>
                </td>
              </tr>
              <tr>
                <th>Duration</th>
                <td>
                <% for (@{$obj->{durations} || []}) { %>
                    <span class="badge alert-warning"><%= $_ %></span>
                <% } %>
                </td>
              </tr>
              <% if ($obj->{mpaa}) { %>
              <tr>
                <th>MPAA</th>
                <td><span class="badge alert-warning"><%= $obj->{mpaa} %></span></td>
              </tr>
              <% } %>
              <% if ($obj->{kind}) { %>
              <tr>
                <th>Kind</th>
                <td><span class="badge alert-warning"><%= $obj->{kind} %></span></td>
              </tr>
              <% } %>
              <% if ($obj->{ratio}) { %>
              <tr>
                <th>Ratio</th>
                <td><span class="badge alert-warning"><%= $obj->{ratio} %></span></td>
              </tr>
              <% } %>

            <% for (@{$obj->{files} || []}) { %>
              <tr>
                <th>Filename</th>
                <td><span class="badge alert-success"><%= $_->{file_name} %></span></td>
              </tr>
              <tr>
                <td>&nbsp;</td>
                <td>
                    <table class="table-striped details">
                      <tr>
                        <th>Filesize</th>
                        <td><span class="badge alert-warning"><%= $_->{actual_size} %></span></td>
                      </tr>
                      <tr>
                        <th>Duration</th>
                        <td><span class="badge alert-warning"><%= $_->{actual_duration} %></span></td>
                      </tr>
                      <tr>
                        <th>Ratio</th>
                        <td><span class="badge alert-warning"><%= $_->{actual_ratio} %></span></td>
                      </tr>
                      <tr>
                        <th>Dimension</th>
                        <td><span class="badge alert-warning"><%= join 'x', $_->{width}, $_->{height} %></span></td>
                      </tr>
                      <tr>
                        <th>FrameRate</th>
                        <td><span class="badge alert-warning"><%= $_->{frame_rate} %></span></td>
                      </tr>
                    </table>
                </td>
              </tr>
            <% } %>

            </table>
        </td><td align="right" valign="top">
            <img src="<%= $obj->{cover} %>" />
        </td></tr></table>

      </div>
    </div>
  </div>
<% } %>
</div>
