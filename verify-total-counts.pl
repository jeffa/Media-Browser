#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_dbh );
local $/ = "\n";
 
my $dbh = get_dbh();

for ( sort map $_->[0], $dbh->selectall_array( 'SHOW TABLES' ) ) {
    printf "%10s: %d\n", $_, $dbh->selectall_arrayref( "SELECT count(*) FROM $_" )->[0][0];
}
