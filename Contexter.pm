$VERSION = "0.01";

use strict;
use FileHandle;

package Contexter;

# The creation of the universe

# does not sanitize filenames

# file format: first line = definitions (skip • Begin <type>)
# subsequent lines = resources

sub new {

    my $class = shift;

    # 'universe'
    my $source_dir = shift;

    # EVC, EVO, Nova, FH
    my $ev_code = shift;

    # ConText.txt
    my $data_file_suffix = shift;

    # __Data
    my $data_dir_suffix = shift;

    my $sourcefile = "$source_dir/${ev_code}$data_file_suffix";
    my $destdir    = "$source_dir/${ev_code}$data_dir_suffix";

    my $self = {};
    bless ($self, $class);

    open( DATA, '<', $sourcefile );

    if ( ! -e $source_dir ) {
        die "$source_dir does not exist";
    }

    if ( ! -e $destdir ) {
        mkdir("$destdir");
    }

    my $type;

    while (<DATA>) {

        if ( $_ =~ /• Begin (.+)/ ) {
            next if $1 eq 'Output';
            $type = $1;

            open( OUT, ">", "$destdir/$type" );
            OUT->autoflush(1);
        }

        # TODO: Scenario data cleanup - regularize this
        $_ =~ s/Visiblility/Visibility/;

        # Make sure $type is defined
        if ( $type and $_ !~ /^• Begin/ ) {

            $_ =~ s/\t/ /g;

            if ( $type eq 'dësc' or $type eq 'STR#' ) {
                $_ =~ s/\\r/ /g;

             # Interpolate \q quotes into single quotes (doubles are delimiters)
                $_ =~ s/\\q/'/g;
            }
            print OUT $_;


        }
    }
    return $self;
}

return 1;
