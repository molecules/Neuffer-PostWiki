#!/bin/env perl
package Neuffer::PostWiki;
# ABSTRACT: Posts pages to mutants.maizegdb.org

#=============================================================================
# STANDARD MODULES AND PRAGMAS
use 5.010;    # Require at least Perl version 5.10
use strict;   # Must declare all variables before using them
use warnings; # Emit helpful warnings
use autodie;  # Fatal exceptions for common unrecoverable errors (e.g. open)
use Carp qw( croak );   # Throw errors from calling function
use File::Slurp qw( read_file write_file);

#=============================================================================
# ADDITIONAL MODULES
use ConfigReader::Simple;
use Getopt::Long::Descriptive; # Parse @ARGV as command line flags and arguments

use RPC::XML::Client;

# ADDITIONAL MODULES
#=============================================================================
#=============================================================================
# CONSTANTS

my $EMPTY_STRING            = q{};
my $DEFAULT_CONFIG_FILENAME = 'dokuwiki.config';

my @ACTION_FLAGS = qw( list delete dump get put );

#
# CONSTANTS
#=============================================================================

#=============================================================================
# Dispatch table

my %sub_for = (
    delete=> \&delete_pages,
    dump  => \&dump_pages,
    get   => \&get_pages,
    put   => \&put_pages,
    list  => \&list_pages,
);

#
# CONSTANTS
#=============================================================================

#=============================================================================
# COMMAND LINE

# Run as a command-line program if not used as a module
main(@ARGV) if !caller();

sub main {

    #-------------------------------------------------------------------------
    # COMMAND LINE INTERFACE                                                 #
    #                                                                        #
    my ($opt, $usage) = describe_options(
        '%c %o <some-arg>',
        [ 'dump=s',    "[page_name(s)] output page(s)'s wiki text to screen",           ],
        [ 'get=s',     "[page_name(s)] download each 'page_name' to 'page_name.txt'",   ],
        [ 'put=s',     "[page_name(s)] upload each 'page_name.txt'",                    ],
        [ 'list',      'list pages on the site',                                        ],
        [ 'delete=s',  'delete page(s)',                                                ],
        [],
        [ 'config=s',    "configuration file (default: $DEFAULT_CONFIG_FILENAME)",        ],
        [],
        [ 'help', 'print usage message and exit'                                        ],
    );


    my $exit_with_usage = sub {
        print "\nUSAGE:\n";

        # Print usage text provided by Getopt::Long::Descriptive
        print $usage->text();

        # Add note describing how to format page names
        say   'Multiple pages should be in quotes and be space-delimited. '
             .'Use underscores for spaces internal to a name (e.g. '
             .'"dwarf_plant" instead of "dwarf plant").';

        exit();
    };

    # If requested, give usage information regardless of other options
    $exit_with_usage->() if $opt->help;

    # Make some flags required
    my $action_count = 0;
    my $action;
    my $page_string;
    for my $flag (@ACTION_FLAGS) {
        if (defined $opt->$flag){
            $action_count++;
            $action = $flag;
            $page_string = $opt->$flag // $EMPTY_STRING;
        }
    }

    # Exit with usage statement if more or less than one action used
    $exit_with_usage->() if $action_count != 1;

    my $config_filename = $opt->config // $DEFAULT_CONFIG_FILENAME; #                                                                        #
    my @config_filenames = ($config_filename, map { ('../' x $_) . ".pass/$config_filename" } 1 .. 5);

    my @actual_config_filenames = grep {-e $_} @config_filenames; 
    my $actual_config_filename = $actual_config_filenames[0];

    if ( ! defined $actual_config_filename){
        die  "Configuration file '$config_filename' not found";
    }

    my $config = ConfigReader::Simple->new($actual_config_filename, []);

    # COMMAND LINE INTERFACE                                                 #
    #-------------------------------------------------------------------------

    #-------------------------------------------------------------------------
    #                                                                        #
    #                                                                        #

    process( { 
                action => $action,
                pages  => $page_string,
                config => $config,
             },
    );

    return;

    #                                                                        #
    #                                                                        #
    #-------------------------------------------------------------------------
}

# COMMAND LINE
#=============================================================================

#=============================================================================
#

sub process {
    my $opt    = shift;
    my $action = $opt->{action};
    my $pages  = $opt->{pages};
    my $config = $opt->{config};

    my $client = get_connection($config);

    # Dispatch based on action
    $sub_for{$action}->($client, $pages);

    return;
}

sub get_connection {
    my $config = shift;
    my $login  = $config->get('login') // die 'configuratoin parameter "login" not set';
    my $site   = $config->get('site')  // die 'configuratoin parameter "site" not set';
    my $pass   = $config->get('pass')  // die 'configuratoin parameter "pass" not set';
    chomp( $site, $pass, $login );

    my $client = RPC::XML::Client->new(
        $site,
        useragent => [ cookie_jar => { file => "$ENV{HOME}/.cookies.txt" } ],
    );

    my $logged_on_ok =
      $client->send_request( 'dokuwiki.login', $login, $pass);

    die "Not logged on" if ! $logged_on_ok;

    return $client;
}

sub put_pages {
    my ($client, $pages_string) = @_;
    
    my @pages = parse_page_names($pages_string);


    for my $page (@pages){
        
        # Split page names into namespaces, if applicable
        my @namespaces = split /:/, $page;

        my $namespace_prependage = $EMPTY_STRING;

        # Change page name to just be the lowest namespace, if it consists of
        #   multiple name spaces
        if(@namespaces > 1){
            my $num_namespaces = $#namespaces; # i.e. one less than count of array elements
            $namespace_prependage = join(":", @namespaces[0 .. $num_namespaces - 1]) . ':' ;
            $page                 = $namespaces[-1]; # last element of namespaces is page name
        }

        # Post page content on the wiki
        my $page_content = read_file("$page.txt");
        $client->send_request( 'wiki.putPage', $namespace_prependage . $page, $page_content);
    }

    return;
}

sub get_pages {
    my ($client, $pages_string) = @_;
    
    my @pages = parse_page_names($pages_string);

    for my $page (@pages){

        my $page_content = get_wiki_text($client, $page);
        write_file("$page.txt", $page_content);
    }

    return;
}

sub dump_pages {

    my ($client, $pages_string) = @_;
    
    my @pages = parse_page_names($pages_string);

    for my $page (@pages){

        my $page_content = get_wiki_text($client, $page);
        say $page_content;
    }

    return;
}

sub get_wiki_text {
    my $client      = shift;
    my $page_name   = shift;
    my $page_object = $client->send_request( 'wiki.getPage', $page_name );
    my $wiki_text   = $page_object->value;
    return $wiki_text;
}

sub delete_pages {
    my ($client, $pages_string) = @_;
    
    my @pages = parse_page_names($pages_string);

    for my $page (@pages){

        # Posting an empty page is the same as deleting it
        $client->send_request( 'wiki.putPage', $page, $EMPTY_STRING);
    }

    return;
}

sub list_pages {
    my $client = shift; 

    my $pages_object = $client->send_request( 'dokuwiki.getPagelist'); 
    my $page_aref_of_href = $pages_object->value;
    for my $href ( @{ $page_aref_of_href }){
        say $href->{id};
    }
    return;
}

sub parse_page_names {
    my $pages_string = shift;
    my @pages = (split /\s+/, $pages_string);
    return (@pages);
}

#
##
##=============================================================================
#
##-----------------------------------------------------------------------------
#
1;  #Modules must return a true value

=pod


=head1 SYNOPSIS

    perl Neuffer/PostWiki.pm --delete page_name
    perl Neuffer/PostWiki.pm --put    page_name
    perl Neuffer/PostWiki.pm --get    page_name
    perl Neuffer/PostWiki.pm --dump   page_name > dumped_filename

=head1 DEPENDENCIES

    File::Slurp
    ConfigReader::Simple
    Getopt::Long::Descriptive
    RPC::XML::Client;

=head1 INCOMPATIBILITIES

    Tested only Linux.
    None known

=head1 BUGS AND LIMITATIONS

     There are no known bugs in this module.
     Please report problems to author.
     Patches are welcome.
