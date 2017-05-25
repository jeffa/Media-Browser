#!perl -T
use strict;
use warnings FATAL => 'all';
use Test::More tests => 1;

use_ok( 'MovieUtil' ) or BAIL_OUT( "can't use module" );
