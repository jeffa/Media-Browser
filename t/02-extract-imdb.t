#!perl -T
use strict;
use warnings FATAL => 'all';
use Test::More tests => 4;

use MovieUtil qw( extract_imdb );

is extract_imdb( 'http://www.imdb.com/title/tt2518788/' ), 'tt2518788';
is extract_imdb( 'http://www.imdb.com/title/tt0078748' ), 'tt0078748';
is extract_imdb( 'http://www.imdb.com/title/tt1954483/?ref_=tt_rec_tt' ), 'tt1954483';
is extract_imdb( "http://www.imdb.com/title/tt1954483/?ref_=tt_rec_tt\n" ), 'tt1954483';
