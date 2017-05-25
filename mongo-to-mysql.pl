#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;

use DBI;
use open ':std', ':encoding(UTF-8)';
 
use lib 'lib';
use MovieUtil qw( get_raw_titles get_credentials );

my $dbh = DBI->connect(
    'DBI:mysql:database=media', get_credentials(),
    { RaiseError => 1 },
);
$dbh->{mysql_enable_utf8} = 1;

my $titles = get_raw_titles();

my $iter = $titles->find();
while (my $movie = $iter->next) {

    my $title_id;
    my $meta = $movie->{meta};

    unless ($movie->{imdb_id} =~ /^tt\d{7}$/) {
        warn "skipping $movie->{filename}: no IMDB ID\n";
        next;
    }

    if (my ($sth) = $dbh->selectall_array( 'SELECT title_id from titles WHERE imdb_id = ?', undef, $movie->{imdb_id} )) {
        $title_id = $sth->[0];
        warn "$title_id: IMDB ID already processed\n";

        if (my ($sth) = $dbh->selectall_array( 'SELECT file_id from files WHERE file_name = ?', undef, $movie->{filename} )) {
            warn "$title_id: Filename already processed: $movie->{filename}\n";
            next;
        }

        $dbh->do( 'INSERT INTO files(
                file_name,
                title_id
            ) VALUES (?, ? )', undef,
            $movie->{filename},
            $title_id
        );

        warn "$title_id: added file $movie->{filename}\n";
        next;
    }

    # insert title info
    $dbh->do( 'INSERT INTO titles(
            imdb_id,
            title,
            year,
            kind,
            ratio,
            rating,
            cover,
            story,
            tagline
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', undef,
        $movie->{imdb_id},
        $meta->{title},
        $meta->{year},
        $meta->{kind},
        $meta->{ratio},
        $meta->{rating},
        $meta->{cover},
        $meta->{story},
        $meta->{tagline},
    );

    # obtain new title_id
    $title_id = $dbh->{mysql_insertid};
    warn "inserted $movie->{imdb_id}: new title ID $title_id\n";

    # insert file using title_id
    $dbh->do( 'INSERT INTO files(
            file_name,
            title_id
        ) VALUES (?, ?)', undef,
        $movie->{filename},
        $title_id
    );
    warn "$title_id: added file $movie->{filename}\n";

    # insert duration(s) using title_id
    my %unique_duration;
    for my $duration (@{ $meta->{duration} }) {

        if ($unique_duration{$duration}++) {
            warn "$title_id: repeated duration: $duration\n";
        } else {

            $dbh->do( 'INSERT INTO durations(
                    duration,
                    title_id
                ) VALUES (?, ?)', undef,
                $duration,
                $title_id
            );
        }
    }

    # check genres
    for my $genre (map lc($_), @{ $meta->{genres} }) {

        my $genre_id;
        my ($sth) = $dbh->selectall_array(
            'SELECT genre_id from genres WHERE genre_name = ?',
            undef, $genre
        );

        if ($sth->[0]) {
            $genre_id = $sth->[0];
        } else{
            # insert any new genre
            $dbh->do( 'INSERT INTO genres(genre_name)
                VALUES (?)', undef,
                $genre,
            );
            $genre_id = $dbh->{mysql_insertid};
            warn "$title_id: added new genre $genre\n";
        }

        # insert genre_xref using title and genre ids
        $dbh->do( 'INSERT INTO genre_xref(
                genre_id,
                title_id
            ) VALUES (?, ?)', undef,
            $genre_id,
            $title_id
        );
        warn "$title_id: added genre_xref $genre_id\n";
    }

    # check director names
    for my $director (@{ $meta->{directors} }) {
        my $name    = $director->{name};
        my $imdb_id = $director->{id};

        my $person_id;
        my ($sth) = $dbh->selectall_array(
            'SELECT person_id from people WHERE imdb_id = ?',
            undef, $imdb_id
        );

        if ($sth->[0]) {
            $person_id = $sth->[0];
        } else{
            # insert any new names
            $dbh->do( 'INSERT INTO people(imdb_id, person_name)
                VALUES (?, ?)', undef,
                $imdb_id,
                $name,
            );
            $person_id = $dbh->{mysql_insertid};
            warn "$title_id: added new person $name\n";
        }
        # insert roles_xref for director using title and name ids
        eval {
            $dbh->do( 'INSERT INTO role_xref(
                    role_id,
                    person_id,
                    title_id
                ) VALUES (?, ?, ?)', undef,
                1,
                $person_id,
                $title_id
            );
        };
        if ($@) {
            warn "$@\n";
        } else {
            warn "$title_id: added role_xref $person_id\n";
        }
    }

    # check writer names
    for my $writer (@{ $meta->{writers} }) {
        my $name    = $writer->{name};
        my $imdb_id = $writer->{id};

        my $person_id;
        my ($sth) = $dbh->selectall_array(
            'SELECT person_id from people WHERE imdb_id = ?',
            undef, $imdb_id
        );

        if ($sth->[0]) {
            $person_id = $sth->[0];
        } else{
            # insert any new names
            $dbh->do( 'INSERT INTO people(imdb_id, person_name)
                VALUES (?, ?)', undef,
                $imdb_id,
                $name,
            );
            $person_id = $dbh->{mysql_insertid};
            warn "$title_id: added new person $name\n";
        }

        # insert roles_xref for writer using title and name ids
        eval {
            $dbh->do( 'INSERT INTO role_xref(
                    role_id,
                    person_id,
                    title_id
                ) VALUES (?, ?, ?)', undef,
                2,
                $person_id,
                $title_id
            );
        };
        if ($@) {
            warn "$@\n";
        } else {
            warn "$title_id: added role_xref $person_id\n";
        }
    }
}
