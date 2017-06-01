#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use Mojolicious::Lite;
use Data::SpreadPagination;
use DBI;

use lib 'lib';
use MovieUtil qw( get_credentials );

my $PER_PAGE = 20;
my $MAX_PAGE = 10;

my $dbh = dbh();

my %valid_fields = map {( $_ => 1 )} qw( title year genre director writer );

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

    $field = 'title' unless $valid_fields{$field};

    unless ($dbh->ping) {
        warn "Re-obtaing DB handle\n";
        $dbh = dbh();
    }

    my $predicate = '';
    if ($query) {
        $predicate = sprintf ' WHERE %s %s "%s%s%s"', 
            $field,
            ($pre || $post ? 'LIKE' : '='),
            ($pre  ? '%' : ''),
            $query,
            ($post ? '%' : ''),
        ;
    }
    warn "QUERY: $query\n PRED: $predicate\n";

    my $sql = 'SELECT count(*) FROM titles' . $predicate;
    my ($total) = $dbh->selectall_array( $sql );

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

    $sql = sprintf 'SELECT * FROM titles %s ORDER BY coalesce(sort,title),year LIMIT %d,%d', $predicate, $pager->first - 1, $per;
    my $titles = $dbh->selectall_arrayref( $sql, {Slice=>{}} );

    for (@$titles) {

        $_->{files} = [
            map $_->[0], $dbh->selectall_array('
                SELECT file_name
                FROM files f
                INNER JOIN titles t ON f.title_id=t.title_id
                WHERE t.title_id = ?
            ', undef, $_->{title_id} )
        ];

        $_->{durations} = [
            map $_->[0], $dbh->selectall_array('
                SELECT duration
                FROM durations d
                INNER JOIN titles t ON d.title_id=t.title_id
                WHERE t.title_id = ?
            ', undef, $_->{title_id} )
        ];

        $_->{genres} = [
            map $_->[0], $dbh->selectall_array('
                SELECT genre_name
                FROM genres g
                INNER JOIN genre_xref x ON g.genre_id=x.genre_id
                INNER JOIN titles t on x.title_id=t.title_id
                WHERE t.title_id = ?
            ', undef, $_->{title_id} )
        ];

        $_->{directors} = 
            $dbh->selectall_arrayref('
                SELECT p.person_name, p.imdb_id
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
                SELECT person_name, p.imdb_id
                FROM people p
                INNER JOIN role_xref x ON p.person_id = x.person_id
                INNER JOIN titles t ON x.title_id = t.title_id
                INNER JOIN roles r ON x.role_id = r.role_id
                WHERE t.title_id = ?
                AND r.role_name = ?
            ', {Slice=>{}}, $_->{title_id}, 'writer' )
        ;
    }

    $self->stash( titles => $titles, pager => $pager, total => $total->[0] || 'No', per => $per, curr => $curr );
    $self->render( template => 'results' );
};

app->start( daemon => '-l', 'http://*:3000' );

sub dbh {
    my $dbh = DBI->connect(
        'DBI:mysql:database=media', get_credentials(),
        { RaiseError => 1 },
    );
    $dbh->{mysql_enable_utf8} = 1;
    return $dbh;
}


__DATA__
@@ index.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title>Movie Collection Browser</title>
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" />
    <style type="text/css">
        table.details { width: 100%; }
        table.details th { text-align: right; valign: top; }
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
                {name: "field",     value: document.search.field.value},
                {name: "pre",       value: document.search.pre.value},
                {name: "post",      value: document.search.post.value},
                {name: "query",     value: document.search.query.value},
                {name: "per",       value: document.search.per.value},
                {name: "curr",      value: curr}
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
        <div id="content" class="col-md-6">
            <div id="results"></div>
        </div>
        <div class="col-md-6">
            <br />
            <form class="form-inline" action="javascript: void(0);" id="search" name="search" class="navbar-search">

                <select name="field" class="form-control">
                  <option value="title">Title</option>
                  <option value="year">Year</option>
                <!--
                  <option value="genre">Genre</option>
                  <option value="director">Director</option>
                  <option value="writer">Writer</option>
                -->
                </select>

                <div class="btn-group" data-toggle="buttons">
                  <label onclick="javascript: toggle('pre')" class="btn btn-default active"><input type="checkbox" checked="1" />%</label>
                </div>

                <input name="query" id="appendedInputButton" class="form-control" type="text" placeholder="ALL" />

                <div class="btn-group" data-toggle="buttons">
                  <label onclick="javascript: toggle('post')" class="btn btn-default active"><input type="checkbox" checked="1" />%</label>
                </div>

                <button id="go" class="btn btn-primary" type="button" onclick="javascript: fetch_results()" data-loading-text="Loading..."> Search! </button>

                <input id="curr" name="curr" type="hidden" />
                <input id="pre"  name="pre"  type="hidden" value="1" />
                <input id="post" name="post" type="hidden" value="1" />
                <input id="per"  name="per"  type="hidden" value="<%= $per %>" />

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
    $( '#' + param ).val( value ? 0 : 1 );
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
</script>
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

<h2><%= $total %> titles found (<%= $curr * $per - ($per - 1) %> - <%= $curr * $per %>)</h2>

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

        <table class="details" width="50%"><tr><td valign="top">
            <table class="table-striped">
              <tr>
                <th>IMDB ID</th>
                <td><a href="http://www.imdb.com/title/<%= $obj->{imdb_id} %>"><%= $obj->{imdb_id} %></a></td>
              </tr>
              <tr>
                <th>Filenames</th>
                <td><%== join('<br/>', @{ $obj->{files} || [] }) %></td>
              </tr>
              <tr>
                <th>Year</th>
                <td><%= $obj->{year} %></td>
              </tr>
              <tr>
                <th>Director</th>
                <td>
                <% for (@{$obj->{directors} || []}) { %>
                    <a href="http://www.imdb.com/name/<%= $_->{imdb_id} %>"><%= $_->{person_name} %></a><br />
                <% } %>
                </td>
              </tr>
              <tr>
                <th>Writer</th>
                <td>
                <% for (@{$obj->{writers} || []}) { %>
                    <a href="http://www.imdb.com/name/<%= $_->{imdb_id} %>"><%= $_->{person_name} %></a><br />
                <% } %>
                </td>
              </tr>
              <tr>
                <th>Genre</th>
                <td><%= join(', ', @{ $obj->{genres} || [] }) %></td>
              </tr>
              <tr>
                <th>Duration</th>
                <td><%= join(', ', @{ $obj->{durations} || [] }) %></td>
              </tr>
              <% if ($obj->{mpaa}) { %>
              <tr>
                <th>MPAA</th>
                <td><%= $obj->{mpaa} %></td>
              </tr>
              <% } %>
              <% if ($obj->{kind}) { %>
              <tr>
                <th>Kind</th>
                <td><%= $obj->{kind} %></td>
              </tr>
              <% } %>
              <% if ($obj->{ratio}) { %>
              <tr>
                <th>Ratio</th>
                <td><%= $obj->{ratio} %></td>
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

<nav aria-label="Page navigation">
  <ul class="pagination">
     <li class="disabled"><a>Results per page:</a></li>
    <% for my $number (10,20,50,100,200) { %>
      <li class="<%= $number == $per ? 'active' : '' %>">
          <a href="javascript: set_results_per( <%= $number %> );"><%= $number %></a>
      </li>
    <% } %>
  </ul>
</nav>
