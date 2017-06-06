#!/usr/bin/env perl
use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;
use Data::Dumper;
use File::Basename;

use lib 'lib';
use MovieUtil qw( get_dbh );

GetOptions (
    'id=s'      => \my $title_id,
    'dry-run'   => \my $dry_run,
    'no-prompt' => \my $no_prompt,
    'help'      => \my $help,
    'man'       => \my $man,
);
pod2usage( -verbose => 0 ) if $help;
pod2usage( -verbose => 2 ) if $man;
pod2usage( -verbose => 0 ) unless $title_id;

my $dbh = get_dbh();

if ($title_id =~ /^tt\d{7}$/) {
    ($title_id) =  $dbh->selectrow_array( 'select title_id from titles where imdb_id = ?', undef, $title_id );
    die "No imdb_id match for that title_id\n" unless $title_id;
}

{ # titles
    my ($title) = $dbh->selectrow_array( 'select title from titles where title_id = ?', undef, $title_id );
    die "No title found for $title_id\n" unless $title;
    unless ($no_prompt) {
        printf "Really delete %s ?!?! ", $title;
        chomp( my $answer = <STDIN> );
        exit unless $answer =~ /^y/i;
    }
}

{ # durations
    my ($total) = $dbh->selectrow_array( 'select count(*) from durations where title_id = ?', undef, $title_id );
    next unless $total;
    my $sql = "delete from durations where title_id = ? limit $total";
    do_sql( $sql, $title_id );
}

{ # files
    my ($total) = $dbh->selectrow_array( 'select count(*) from files where title_id = ?', undef, $title_id );
    next unless $total;
    my $sql = "delete from files where title_id = ? limit $total";
    do_sql( $sql, $title_id );
}

{ # genres
    my $sth = $dbh->selectall_arrayref( '
        select x.genre_id, count(*) as count
        from genre_xref x 
        inner join genres g on x.genre_id=g.genre_id 
        where x.genre_id in( select genre_id from genre_xref where title_id = ? ) 
        group by x.genre_id
        having count = 1
    ', {Slice=>{}}, $title_id );
    next unless scalar @$sth;
    my $sql = 'delete from genres where genre_id in( ' . join(', ', map $_->{genre_id}, @$sth ) . ' ) limit ' . scalar @$sth;
    do_sql( $sql, $title_id );
}

{ # genre_xref
    my ($total) = $dbh->selectrow_array( 'select count(*) from genre_xref where title_id = ?', undef, $title_id );
    next unless $total;
    my $sql = "delete from genre_xref where title_id = ? limit $total";
    do_sql( $sql, $title_id );
}

{ # people
    my $sth = $dbh->selectall_arrayref( '
        select x.person_id, count(*) as count
        from role_xref x
        inner join people p on x.person_id=p.person_id
        where x.person_id in( select person_id from role_xref where title_id = ? )
        group by x.person_id
        having count = 1
    ', {Slice=>{}}, $title_id );
    next unless scalar @$sth;
    my $sql = 'delete from people where person_id in( ' . join(', ', map $_->{person_id}, @$sth ) . ' ) limit ' . scalar @$sth;
    do_sql( $sql, $title_id );
}

{ # role_xref
    my ($total) = $dbh->selectrow_array( 'select count(*) from role_xref where title_id = ?', undef, $title_id );
    next unless $total;
    my $sql = "delete from role_xref where title_id = ? limit $total";
    do_sql( $sql, $title_id );
}

{ # final title
    my $sql = "delete from titles where title_id = ? limit 1";
    do_sql( $sql, $title_id );
}


sub do_sql {
    my ($sql,@args) = @_;
    my $do_sql = $sql;

    $sql =~ s/\?/$_/ for @args;
    print $sql;

    if ($dry_run) {
        print "\n";
        return;
    }

    $dbh->do( $sql, undef, @args );
    print ": DELETES!!!\n";
}


__END__
=head1 NAME

delete-entry - delete title and all orphaned genre, etc.

=head1 SYNOPSIS

delete-entry --id=XXX --dry-run

 Options:
   --id         title_id or imdb_id
   --dry-run    just show what would have happened
   --no-prompt  do not prompt for deletion confirmation
   --help       show help
   --man        print man page

=head1 OPTIONS

=over 8

=item B<--id>

title_id or imdb_id of entry to delete

    --id=3228

    --id=tt0106246

=item B<--dry-run>

Don't deleted any records, just show what would have happened.

=item B<--no-prompt>

Do not prompt for deletion confirmation.

=back
