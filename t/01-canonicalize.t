#!perl -T
use strict;
use warnings FATAL => 'all';
use Test::More tests => 22;

use MovieUtil qw( canonicalize );

is canonicalize( '1 Life on the Limit 2013 720p.mp4' ), '1 Life on the Limit 2013';
is canonicalize( 'ATHF_Colon_Movie.avi' ), 'ATHF Colon Movie';
is canonicalize( 'CoN1 - The Lion The Witch And The Wardrobe 2005 1080p.mp4' ), 'The Lion The Witch And The Wardrobe 2005';
is canonicalize( 'FT7 Friday the 13th Part VII The New Blood 1988 720p.mp4' ), 'Friday the 13th Part VII The New Blood 1988';
is canonicalize( '/Volumes/MOVIES/1080p/Airplane! 1980 1080p.mp4' ), 'Airplane! 1980';
is canonicalize( '/Volumes/MOVIES/Sets/Bourne/B1 Bourne Identity 2002 1080p.mp4' ), 'Bourne Identity 2002';
is canonicalize( '/Volumes/MOVIES/Sets/James Bond/JB01 Dr. No 1962 HD.mkv' ), 'Dr. No 1962';
is canonicalize( '/Volumes/MOVIES/LD/Mr Mom 1983 4-3.mp4' ), 'Mr Mom 1983';
is canonicalize( '/Volumes/MOVIES/LD/Returner 480p.m4v' ), 'Returner';
is canonicalize( '/Volumes/MOVIES/LD/Tesis VHS.avi' ), 'Tesis';
is canonicalize( '/Volumes/MOVIES/LD/Looker.cd2.avi' ), 'Looker';
is canonicalize( '/Volumes/MOVIES/LD/Liquid Sky 1982 2.avi' ), 'Liquid Sky 1982';
is canonicalize( '/Volumes/MOVIES/720p/Marrying Man aka Too Hot to Handle 1991 720p.mp4' ), 'Marrying Man 1991';

is canonicalize( '/Volumes/MOVIES/LD/Halloween_2007_workprint.avi' ), 'Halloween 2007';
is canonicalize( '/Volumes/MOVIES/LD/Hawk the Slayer - Rifftrax.mp4' ), 'Hawk the Slayer';
is canonicalize( '/Volumes/MOVIES/LD/Highlander II - The Quickening (Theatrical Release).avi' ), 'Highlander II - The Quickening';
is canonicalize( '/Volumes/MOVIES/LD/True Romance recut2.avi' ), 'True Romance';
is canonicalize( '/Volumes/MOVIES/LD/Deer Hunter 1979 pt2.avi' ), 'Deer Hunter 1979';
is canonicalize( '/Volumes/MOVIES/Sets/Star Wars/StWr1 A New Hope (despecialized).mkv' ), 'A New Hope';
is canonicalize( '/Volumes/MOVIES/Sets/Star Wars/StWr78 Rogue One 2016 720p.mp4' ), 'Rogue One 2016';
is canonicalize( '/Volumes/MOVIES/720p/It 1990 Part2 720p.mp4' ), 'It 1990';
is canonicalize( '/Volumes/MOVIES/720p/Catching Milat 2014 Part 1 720p.mp4' ), 'Catching Milat 2014';
