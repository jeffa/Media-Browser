#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use lib 'lib';
use MovieUtil qw( get_dbh );

my $dbh = get_dbh();
my $title_id = int( shift || 0 );

my $sth = $dbh->selectall_arrayref('select tag, tag_id from tags');
my %all = map { @$_ } @$sth;

my @old = tags( $dbh, $title_id );
my $old = join( ' ', @old );
do {print "$old\n"; exit} unless @ARGV;

my %old = map { $_ => 1 } @old;
my $new = join( ' ', sort @ARGV );
my %new = map { $_ => 1 } @ARGV;

my @to_add = map { $old{$_} ? () : $all{$_} || $_ } keys %new;
warn "gonna add '@to_add'\n";
my @tag_ids;
for my $tag (@to_add) {
    if ($tag =~ /\D/) {
        $dbh->do( 'insert into tags(tag) values(?)', undef, $tag );
        push @tag_ids, $dbh->{mysql_insertid};
    } else {
        push @tag_ids, $tag;
    }
}

warn "gonna link '@tag_ids'\n";
for my $tag_id (@tag_ids) {
    $dbh->do( 'insert into tag_xref(tag_id,title_id) values(?,?)', undef, $tag_id, $title_id );
}

my @to_unlink = map { $new{$_} ? () : $all{$_} } keys %old;

my @to_delete;
@to_delete = @{ $dbh->selectcol_arrayref( '
    select x.tag_id, count(*) as count
    from tag_xref x 
    inner join tags t on x.tag_id=t.tag_id 
    where x.tag_id in( ' . join(', ', @to_unlink ) . ')
    group by x.tag_id
    having count = 1
') } if @to_unlink;

if (@to_delete) {
    warn "gonna delete '@to_delete'\n";
    $dbh->do(
        'delete from tags where tag_id in( ' 
        . join(', ', @to_delete ) . ')'
    );
}

if (@to_unlink) {
    warn "gonna unlink '@to_unlink'\n";
    $dbh->do( 
        'delete from tag_xref where title_id = ? and tag_id in( '
        . join(', ', @to_unlink ) . ')',
        undef, $title_id
    );
}

print join( ' ', tags( $dbh, $title_id ) ), $/;



sub tags {
    my ($dbh, $title_id) = @_;
    @{ $dbh->selectcol_arrayref('
        select t.tag
        from tags t
        inner join tag_xref x
        on t.tag_id=x.tag_id
        where x.title_id = ?
        order by t.tag
    ', undef, $title_id ) }
}
