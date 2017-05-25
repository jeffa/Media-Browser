#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use Mojolicious::Lite;
use Data::SpreadPagination;

use lib 'lib';
use MovieUtil qw( get_raw_titles );

my $PER_PAGE = 10;
my $MAX_PAGE = 10;
my $titles = get_raw_titles();

get '/' => sub {
    my $self = shift;
    $self->render( template => 'index' );
};

get '/fetch' => sub {
    my $self = shift;
    my $curr = int( $self->param( 'curr' ) ) || 1;
    my $per  = int( $self->param( 'per'  ) ) || $PER_PAGE;
    my $query = $self->param( 'query' );

    my $pager = Data::SpreadPagination->new({
        totalEntries      => $titles->count,
        entriesPerPage    => 20,
        currentPage       => $curr,
        entriesPerPage    => $per,
        maxPages          => $MAX_PAGE,
    });

    my $find = $query && $query ne 'ALL' 
        ? { 'meta.title' => { '$regex' => $query, '$options' => 'i' } } 
        : { imdb_id => { '$regex' => qr/^tt\d{7}$/ } }
    ;

    my @titles = $titles
        ->find( $find )
        ->sort({ 'meta.title' => 1 })
        ->limit( $per )
        ->skip( $pager->first )
        ->all
    ;
    $self->stash( titles => \@titles, pager => $pager );
    $self->render( template => 'results' );
};

app->start( daemon => '-l', 'http://*:4000' );


__DATA__
@@ index.html.ep
% layout 'default';
<div id="results"></div>

@@ results.html.ep
<nav aria-label="Page navigation">
    <ul class="pagination">
        <li class="<%= $pager->previous_page ? '' : 'disabled' %>" aria-label="Previous">
            <a href="javascript:set_controls( <%= $pager->previous_page %> ); fetch_results();">&laquo;</a>
        </li>
    <% for my $number ($pager->pages_in_spread) { %>
        <% if ($number) { %>
        <li class="<%= $pager->current_page == $number ? 'active' : '' %>">
            <a href="javascript:set_controls( <%= $number %> ); fetch_results();"><%= $number %></a>
        </li>
        <% } else { %>
        <li class="disabled"><a href="javascript:void">...</a></li>
        <% } %>
    <% } %>
        <li class="<%= $pager->next_page ? '' : 'disabled' %>" aria-label="Next">
            <a href="javascript:set_controls( <%= $pager->next_page %> ); fetch_results();">&raquo;</a>
        </li>
    </ul>
</nav>

<% unless (@$titles) { %>
  <h2>No titles found</h2>
<% } %>

<div class="panel-group" id="accordion" role="tablist" aria-multiselectable="false">
<% for my $i (0 .. $#$titles) { %>
  <% my $obj = $titles->[$i]; %>
  <% my ($name,@path) = split( '\/', scalar( reverse $obj->{filename} ), 2 ); %>
  <% $name = scalar reverse $name; @path = map { scalar reverse $_ } @path; %>
  <div class="panel panel-default">
    <div class="panel-heading" role="tab" id="heading-<%= $obj->{_id} %>">
      <h4 class="panel-title">
        <a role="button" data-toggle="collapse" data-parent="#accordion" href="#collapse-<%= $obj->{_id} %>" aria-expanded="<%= $i ? 'true' : 'false' %>" <%= $i ? 'class="collapsed"' : '' %> aria-controls="collapse-<%= $obj->{_id} %>">
            <%= $obj->{meta}{title} %>
        </a>
      </h4>
    </div>
    <div id="collapse-<%= $obj->{_id} %>" class="panel-collapse collapse <%= $i ? '' : 'in' %>" role="tabpanel" aria-labelledby="heading-<%= $obj->{_id} %>">
      <div class="panel-body">

        <table class="details" width="50%"><tr><td valign="top">
            <table class="table-striped">
              <tr>
                <th>IMDB ID</th>
                <td><%= $obj->{imdb_id} %></td>
              </tr>
              <tr>
                <th>Filename</th>
                <td><%= $name %></td>
              </tr>
<!--
              <tr>
                <th>AKA</th>
                <td><%= join(' | ', map { ref($_) ? sprintf( '%s (%s)', $_->{title}, $_->{country} ) : $_ } @{ $obj->{meta}{aka} }) %></td>
              </tr>
-->
              <tr>
                <th>Path</th>
                <td><%= join('/', @path) %></td>
              </tr>
              <tr>
                <th>Year</th>
                <td><%= $obj->{meta}{year} %></td>
              </tr>
              <tr>
                <th>Director</th>
                <td><%= join(', ', map { ref($_) ? $_->{name} : '' } @{ $obj->{meta}{directors} }) %></td>
              </tr>
              <tr>
                <th>Writer</th>
                <td><%= join(', ', map { ref($_) ? $_->{name} : '' } @{ $obj->{meta}{writers} }) %></td>
              </tr>
              <tr>
                <th>Genre</th>
                <td><%= join(', ', @{ $obj->{meta}{genres} || [] }) %></td>
              </tr>
              <tr>
                <th>Duration</th>
                <td><%= join('|', @{ $obj->{meta}{duration} || [] }) %></td>
              </tr>
              <tr>
                <th>Language</th>
                <td><%= join(', ', @{ $obj->{meta}{language} || [] }) %></td>
              </tr>
              <tr>
                <th>Country</th>
                <td><%= join(', ', @{ $obj->{meta}{country} || [] }) %></td>
              </tr>
              <tr>
                <th>MPAA</th>
                <td><%= $obj->{meta}{mpaa} %></td>
              </tr>
              <tr>
                <th>Kind</th>
                <td><%= $obj->{meta}{kind} %></td>
              </tr>
              <tr>
                <th>Ratio</th>
                <td><%= $obj->{meta}{ratio} %></td>
              </tr>
            </table>
        </td><td align="right" valign="top">
            <img src="<%= $obj->{meta}{cover} %>" />
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
        table.details th { text-align: right; }
    </style>
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.12.4/jquery.min.js"></script>
    <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>
    <script type="text/javascript">

        function load() {
            // enter key "submits" the form
            $(document).keydown(function(e) {
                switch(e.which) {
                    case 13:
                    fetch_results();
                    default: return;
                }
                e.preventDefault();
            });

            document.search.curr.value = 1;
            fetch_results();
        }

        function fetch_results() {

            var query = document.search.query.value;
            var curr  = document.search.curr.value;
            if (!curr) { curr = 1 }

            var params = $.param([
                {name: "curr",  value: document.search.curr.value},
                {name: "query", value: document.search.query.value}
            ]);

            var url  = '/fetch?' + params;
            _ajaxGET( url, '#results' );
        }

        function set_controls( curr ) {
            document.search.curr.value = curr;
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
        <div id="content" class="col-md-6"><%= content %></div>
        <div id="content" class="col-md-6">
            <form action="javascript:void(0);" id="search" name="search" class="navbar-search">

                <p>&nbsp;</p>

                <div class="input-append">
                    <input name="query" id="appendedInputButton" type="text" value="ALL" />
                    <button class="btn btn-primary" type="button" onclick="javascript: fetch_results()">Go!</button>
                </div>

                <input name="curr" type="hidden" />
                <input name="per"  type="hidden" />

            </form>
        </div>
      </div>
    </div>
  </body>
</html>
