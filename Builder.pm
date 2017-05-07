$VERSION = "0.01";

use strict;
use warnings;

use Storable qw(nstore retrieve);
use File::Path;
use WWW::Curl::Easy;

use Contexter;
use Galaxy;

package Builder;

sub new {
    my $class = shift;
    my $ev_code = shift; #(EVC UTF8EVO FH Nova)

    my $self = {};
    bless ($self, $class);

    my $base_url = "https://raw.githubusercontent.com/adamreiser/evnova-utils/master/Context/";
    my $url       = '';
    my $data_file = '';

    my $dest_dir = "universe";

    if ( ! -e $dest_dir ) {
        mkdir "$dest_dir";
    }

    print "Building $ev_code...\n";

    my $suffix = 'ConText.txt';

    # inconsistency in github files
    if ( $ev_code eq "UTF8EVO" ) {
        $suffix = 'Context.txt';
    }

    $url       = "$base_url${ev_code}$suffix";
    $data_file = "${ev_code}$suffix";

    if ( -e "$dest_dir/${ev_code}.db" ) {
        print "\tDeleting $dest_dir/${ev_code}.db\n";
        unlink "$dest_dir/${ev_code}.db";
    }

    if ( ! -e "$dest_dir/$data_file" ) {
        open (my $data_fh, '>', "$dest_dir/$data_file")
            or die "Unable to open $dest_dir/$data_file!";
        my $curl = WWW::Curl::Easy->new;
        print "\tDownloading\n\t$url\n";
        print "\t\t-> $dest_dir/$data_file\n";

        $curl->setopt(WWW::Curl::Easy::CURLOPT_HEADER,    1 );
        $curl->setopt(WWW::Curl::Easy::CURLOPT_URL,       $url );
        $curl->setopt(WWW::Curl::Easy::CURLOPT_WRITEDATA, $data_fh );

        my $retcode = $curl->perform;

        if ( $retcode == 0 ) {
            print("\tTransfer went ok\n");
            my $response_code = $curl->getinfo(WWW::Curl::Easy::CURLINFO_HTTP_CODE);
        }
        else {
            die(    "\tError: $retcode "
                  . $curl->strerror($retcode) . " "
                  . $curl->errbuf
                  . "\n" );
        }
    }

    else {
        print "\t$dest_dir/$data_file exists, not downloading\n";
    }

    # 'universe', evcode, filename suffix, data dir suffix
    Contexter->new( $dest_dir, $ev_code, $suffix, '__Data' );

    # Creates a galaxy from contents of $dest_dir
    my $galaxy_object = Galaxy->new( $ev_code, $dest_dir );

    Storable::nstore( $galaxy_object, "${dest_dir}/${ev_code}.db" );

    if ( -d "${dest_dir}/${ev_code}__Data" ) {
        print "\tDeleting ${dest_dir}/${ev_code}__Data\n";
        File::Path::rmtree("${dest_dir}/${ev_code}__Data");
    }

    return $self;
}

return 1;
