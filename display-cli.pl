#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_dbh );

my $dbh = get_dbh();

my $id = shift;
die "Must supply title or IMDb ID\n" unless $id;
my $field = $id =~ /^tt\d{7}$/ ? 'imdb_id' : 'title_id';

my $sth = $dbh->selectall_arrayref( 
    "select * from titles where $field = ?",
    {Slice => {}},
    $id,
);

my @tags = @{ $dbh->selectcol_arrayref(
    'SELECT tag FROM tags INNER JOIN tag_xref x ON tags.tag_id=x.tag_id WHERE x.title_id = ?',
    undef, $sth->[0]{title_id}
) };


print Dumper $sth;
print Dumper \@tags;
