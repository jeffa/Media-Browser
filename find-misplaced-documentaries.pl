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

    my @files = map $_->[0], $dbh->selectall_array('
        SELECT file_name
        FROM files
        WHERE title_id = ?
        AND file_name LIKE ?
    ', undef, $title_id, '/Volumes/MOVIES/%' );

    next unless @files;
    print "$_\n" for @files;
}
