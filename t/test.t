use 5.008;    # Require at least Perl version 5.8
use strict;   # Must declare all variables before using them
use warnings; # Emit helpful warnings
use autodie;  # Fatal exceptions for common unrecoverable errors (e.g. w/open)

# Testing-related modules
use Test::More;                  # provide testing functions (e.g. is, like)
use Test::LongString;            # Compare strings byte by byte
use Data::Section -setup;        # Set up labeled DATA sections
use File::Temp  qw( tempfile );  #
use File::Slurp qw( read_file write_file   );  # Read a file into a string

{
    my $page_name     = 'test';
    my $page_filename = "$page_name.txt";

    assign_filename_for($page_filename, $page_name);

    # Delete page (if it exists)
    system("perl lib/Neuffer/PostWiki.pm --delete $page_name");

    # Put up a new copy of it
    system("perl lib/Neuffer/PostWiki.pm --put  $page_name");

    # Delete copy on the local filesystem
    delete_temp_file($page_filename); # Note that file is DELETED

    # Download page from web
    system("perl lib/Neuffer/PostWiki.pm --get $page_name ");
   
    # Check that downloaded file is the same as original
    my $results = read_file($page_filename); # Note that file has been RECREATED due to the download 
    my $expected = string_from($page_name);
    is_string($results,$expected,'Created page, downloaded it, and it is same as expected');

    # Dump page contents from web
    my $dumped_filename = 'test_dumped.txt';
    system("perl lib/Neuffer/PostWiki.pm --dump $page_name > $dumped_filename");

    my $results_dumped = read_file($dumped_filename);

    # Remove extra newline character
    chomp $results_dumped;

    is_string($results_dumped, $expected, 'Dumped content from web page correctly');

    # delete temp files
    delete_temp_file($page_filename);
    delete_temp_file($dumped_filename);

    # Delete page to leave the web app the same as before
    system("perl lib/Neuffer/PostWiki.pm --delete $page_name");
}

done_testing();

sub sref_from {
    my $section = shift;

    #Scalar reference to the section text
    return __PACKAGE__->section_data($section);
}

sub string_from {
    my $section = shift;

    #Get the scalar reference
    my $sref = sref_from($section);

    #Return a string containing the entire section
    return ${$sref};
}

sub fh_from {
    my $section = shift;
    my $sref    = sref_from($section);

    #Create filehandle to the referenced scalar
    open( my $fh, '<', $sref );
    return $fh;
}

sub assign_filename_for {
    my $filename = shift;
    my $section  = shift;

    # Don't overwrite existing file
    die "'$filename' already exists." if -e $filename;

    my $string   = string_from($section);
    open(my $fh, '>', $filename);
    print {$fh} $string;
    close $fh;
    return;
}

sub filename_for {
    my $section           = shift;
    my ( $fh, $filename ) = tempfile();
    my $string            = string_from($section);
    print {$fh} $string;
    close $fh;
    return $filename;
}

sub temp_filename {
    my ($fh, $filename) = tempfile();
    close $fh;
    return $filename;
}

sub delete_temp_file {
    my $filename  = shift;
    my $delete_ok = unlink $filename;
    ok($delete_ok, "deleted temp file '$filename'");
}

#------------------------------------------------------------------------
# IMPORTANT!
#
# Each line from each section automatically ends with a newline character
#------------------------------------------------------------------------

__DATA__
__[ test ]__
This is a test
