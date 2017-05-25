#!/usr/bin/env perl
use strict;
use warnings;
use Mojolicious::Lite;
use MongoDB;
use HTML::TableExtract;
use File::Basename;

my $client = MongoDB->connect( 'mongodb://localhost' );
my $db = $client->get_database( 'movies' );

get '/' => sub {
    my $c = shift;
    my @titles = $db->get_collection( 'raw_titles' )
        ->find({ imdb_id => { '$exists' => 0 } })
        ->sort({ term => 1 })
        ->limit( 20 )
        ->all
    ;

    for (@titles) {
        my $te = HTML::TableExtract->new(
            attribs => { class => 'findList' },
            keep_html => 1,
        );
        $te->parse( $_->{search} );
        (my $table) = $te->tables;
        $_->{matches} = [ map {
            my ($id) = m{"/title/([^/]+)[^>]+([^<]+)};
            s/<[^>]+>//g;
            [ $id, $_ ];
        } @{ ($table->columns)[1] } ] if $table;
        push @{ $_->{matches} }, [qw( SKIP SKIP )];
        $_->{filename} = basename( $_->{filename} );
    }
    $c->stash( titles => \@titles );
    $c->render( template => 'index' );
};

get '/update/:mongo_id/:imdb_id' => sub {
    my $c = shift;
    my $mongo_id = $c->param( 'mongo_id' );
    my $imdb_id  = $c->param( 'imdb_id' );
    $db->get_collection( 'raw_titles' )->update_many(
        { _id => MongoDB::OID->new( value => $mongo_id ) },
        { '$set' => {imdb_id => $imdb_id} }
    );
    $c->stash( mongo_id => $mongo_id, imdb_id => $imdb_id );
    $c->render( template => 'update' );
};

app->start( daemon => '-l', 'http://*:4000' );
__DATA__
@@ index.html.ep
% layout 'default';
<form>
<h1>Titles:</h1>
<% for my $obj (@$titles) { %>
    <div class="alert alert-success alert-<%= $obj->{_id} %>">
    <h2><%= $obj->{term} %></h2>
    <p><%= $obj->{filename} %> (<%= $#{$obj->{matches}} %> hits)</p>
<%      for my $match (@{$obj->{matches}}) { %>
        <input type="radio"
            value="<%= $match->[0] %>"
            name="<%= $obj->{_id} %>"
            onchange="javascscript: update_id( '<%= $obj->{_id} %>', '<%= $match->[0] %>' )"
            <%= $obj->{imdb_id} && $match->[0] eq $obj->{imdb_id} ? 'checked' : '' %>
        />
<%          if ($match->[0] eq 'SKIP') { %>
                <%= $match->[1] %>
<%          } else { %>
                <%= link_to $match->[1] => "http://www.imdb.com/title/$match->[0]", target => '_blank' %><br />
<%          } %>
<%      } %>
    </div>
<% } %>
</form>
<p> <a href="/">next batch</a> </p>

@@ update.html.ep
Update <%= $mongo_id %> => <%= $imdb_id %>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title>IMDb Title Matcher</title>
    <link rel="stylesheet" href="http://unlocalhost.com/css/bootstrap.css" />
    <link rel="stylesheet" href="http://unlocalhost.com/css/style.css" />
    <script src="http://unlocalhost.com/js/jquery.min.js"></script>
    <script src="http://unlocalhost.com/js/bootstrap.min.js"></script>
    <script type="text/javascript">
    function update_id( mongo_id, imdb_id ) {
        _ajaxGET( '/update/' + mongo_id + '/' + imdb_id, '#result-list' );
        $( ".alert-" + mongo_id ).alert( 'close' );
    }

    function _ajaxGET( url, id, err ) {

        if (!err) {
            err = '<div class="alert alert-error">'
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
                //$( id ).html( $( id ).html() + '<br/>' + xhr.responseText );
                $( id ).append( '<li>' + xhr.responseText + '</li>' );
            },
            error: function( xhr, status, error ) {
                $( id ).html( err );
            }
        });
    }
    </script>    
  </head>
  <body>
    <div class="container-fluid">
      <div class="row-fluid">
        <div class="span8"><%= content %></div>
        <div class="span4" id="result" style="position:fixed; right: 0">
            <ol id="result-list"></ol>
        </div>
      </div>
    </div>
  </body>
</html>
