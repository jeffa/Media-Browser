#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use Mojolicious::Lite;
use Data::SpreadPagination;
use DBI;

use lib 'lib';
use MovieUtil qw( get_credentials );

my $PER_PAGE = 10;
my $MAX_PAGE = 10;

my $dbh = dbh();

get '/' => sub {
    my $self = shift;
    $self->render( template => 'index' );
};

get '/fetch' => sub {
    my $self = shift;
    my $curr = int( $self->param( 'curr' ) ) || 1;
    my $per  = int( $self->param( 'per'  ) ) || $PER_PAGE;
    my $query = $self->param( 'query' );

    unless ($dbh->ping) {
        warn "Re-obtaing DB handle\n";
        $dbh = dbh();
    }

    my $search = ($query && $query ne 'ALL') ? " WHERE title LIKE '%$query%'" : '';
    my $sql = 'SELECT count(*) FROM titles' . $search;
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

    $sql = sprintf 'SELECT * FROM titles %s ORDER BY coalesce(sort,title),year LIMIT %d,%d', $search, $pager->first - 1, $per;
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
% layout 'default';
<div id="results"></div>

@@ results.html.ep
<nav aria-label="Page navigation">
    <ul class="pagination">
        <li class="<%= $pager->previous_page ? '' : 'disabled' %>" aria-label="Previous">
            <a href="javascript:fetch_results( <%= $pager->previous_page %> );">&laquo;</a>
        </li>
    <% for my $number ($pager->pages_in_spread) { %>
        <% if ($number) { %>
        <li class="<%= $pager->current_page == $number ? 'active' : '' %>">
            <a href="javascript:fetch_results( <%= $number %> );"><%= $number %></a>
        </li>
        <% } else { %>
        <li class="disabled"><a href="javascript:void">...</a></li>
        <% } %>
    <% } %>
        <li class="<%= $pager->next_page ? '' : 'disabled' %>" aria-label="Next">
            <a href="javascript:fetch_results( <%= $pager->next_page %> );">&raquo;</a>
        </li>
    </ul>
</nav>

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
                <td>&nbsp;</td>
              </tr>
              <tr>
                <th>Language</th>
                <td>&nbsp;</td>
              </tr>
              <tr>
                <th>Country</th>
                <td>&nbsp;</td>
              </tr>
              <tr>
                <th>MPAA</th>
                <td><%= $obj->{mpaa} %></td>
              </tr>
              <tr>
                <th>Kind</th>
                <td><%= $obj->{kind} %></td>
              </tr>
              <tr>
                <th>Ratio</th>
                <td><%= $obj->{ratio} %></td>
              </tr>
            </table>
        </td><td align="right" valign="top">
            <img src="<%= $obj->{cover} %>" />
        </td></tr></table>

      </div>
    </div>
  </div>
<% } %>
</div>


@@ layouts/default.html.ep
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
            // enter key "submits" the form
            $(document).keydown(function(e) {
                switch(e.which) {
                    case 13:
                    fetch_results( 1 );
                    default: return;
                }
                e.preventDefault();
            });

            fetch_results( 1 );
        }

        function set_results_per( per ) {
            document.search.per.value = per;
            fetch_results( 1 );
        }

        function fetch_results( curr ) {

            var params = $.param([
                {name: "query", value: document.search.query.value},
                {name: "per",   value: document.search.per.value},
                {name: "curr",  value: curr}
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

            $.ajax( {
                url: url,
                type: 'GET',
                success: function( data, status, xhr ) {
                    $( id ).html( xhr.responseText );
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
        <div id="content" class="col-md-8"><%= content %></div>
        <div class="col-md-4">
            <form action="javascript:void(0);" id="search" name="search" class="navbar-search">

                <p>&nbsp;</p>

                <div class="input-append">
                    <input name="query" id="appendedInputButton" type="text" value="ALL" />
                    <button class="btn btn-primary" type="button" onclick="javascript: fetch_results( 1 )">Go!</button>
                </div>

                <input name="curr" type="hidden" />
                <input name="per"  type="hidden" />

            </form>
        </div>
      </div>
    </div>
  </body>
</html>
