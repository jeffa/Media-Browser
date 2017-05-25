#!perl -T
use strict;
use warnings FATAL => 'all';
use Test::More tests => 3;
use utf8;
use Encode qw( encode );

use MovieUtil qw( get_raw_titles get_details );
my ($titles, $title);
$titles = get_raw_titles();

($title) = $titles->find( { imdb_id => 'tt1436045' } )->all;
is $title->{meta}{title}, encode( 'UTF-8', 'Jûsan-nin no shikaku' ), "title decoded correctly";

($title) = $titles->find( { imdb_id => 'tt0110413' } )->all;
is $title->{meta}{title}, encode( 'UTF-8', 'Léon: The Professional' ), "title decoded correctly";

($title) = $titles->find( { imdb_id => 'tt0066473' } )->all;
is $title->{meta}{writers}[2]{name}, encode( 'UTF-8', 'Ryûzô Kikushima' ), "name decoded correctly";

