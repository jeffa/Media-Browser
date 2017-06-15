#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_dbh );
local $/ = "\n";
 
my $dbh = get_dbh();

my @docs = map $_->[0], $dbh->selectall_array('
    SELECT t.title_id
    FROM titles t
    INNER JOIN genre_xref x
    ON t.title_id = x.title_id
    INNER JOIN genres g
    ON x.genre_id = g.genre_id
    WHERE genre_name = "documentary"
');
    

for my $title_id (@docs) {

    my $files = $dbh->selectall_arrayref('
        SELECT file_id, file_name
        FROM files
        WHERE title_id = ?
        AND (file_name LIKE ? OR file_name LIKE ?)
    ', undef, $title_id, '/Volumes/MOVIES/%', '/Volumes/DROBO2/BACKLOG/%' );

    next unless @$files;
    printf "%s,%s\n", @$_ for @$files;
}
