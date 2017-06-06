#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_dbh );
local $/ = "\n";
 
my $dbh = get_dbh();

my @no_year = map $_->[0], $dbh->selectall_array('
    SELECT title_id
    FROM titles
    WHERE year < 1900
');
    

for my $title_id (@no_year) {
    my ($file) = map $_->[0], $dbh->selectall_array('
        SELECT file_name
        FROM files
        WHERE title_id = ?
        LIMIT 1
    ', undef, $title_id );

    my ($year) = $file =~ /(2\d\d\d)/;
    next unless $year;

    $dbh->do( 'update titles set year = ? where title_id = ? limit 1', undef, $year, $title_id );
}
