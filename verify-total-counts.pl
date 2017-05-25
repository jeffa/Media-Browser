#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use DBI;

use lib 'lib';
use MovieUtil qw( get_credentials );
local $/ = "\n";
 
my $dbh = DBI->connect(
    'DBI:mysql:database=media', get_credentials(),
    { RaiseError => 1 },
);

for ( sort map $_->[0], $dbh->selectall_array( 'SHOW TABLES' ) ) {
    printf "%10s: %d\n", $_, $dbh->selectall_arrayref( "SELECT count(*) FROM $_" )->[0][0];
}

__DATA__
 durations: 5498
     files: 4848
genre_xref: 13000
    genres: 25
    people: 7930
 role_xref: 16136
     roles: 2
    titles: 4755
