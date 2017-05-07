$Int::VERSION = "0.01";

package Int;

sub new {

    my $class = shift;
    my $self = {'it' => "\t", 'st' => '', 'x' => 0, 'y' => 0};
    $self->{win} = shift;

    bless( $self, $class );

    if ( Curses::has_colors() ) {
        Curses::start_color();
        Curses::init_pair( 1, $Curses::COLOR_GREEN,  $Curses::COLOR_BLACK );
        Curses::init_pair( 2, $Curses::COLOR_CYAN,   $Curses::COLOR_BLACK );
        Curses::init_pair( 3, $Curses::COLOR_YELLOW, $Curses::COLOR_BLACK );
        Curses::init_pair( 4, $Curses::COLOR_RED,    $Curses::COLOR_BLACK );
        Curses::init_pair( 5, $Curses::COLOR_WHITE,  $Curses::COLOR_BLACK );
        $self->{win}->attron( Curses::COLOR_PAIR(1) );
    }

    return $self;
}

return 1;
