use ExtUtils::MakeMaker ;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    'NAME'         => 'CGI::QuickData',
    'VERSION_FROM' => 'QuickData.pm', # finds $VERSION
    'DISTNAME'     => 'CGI-QuickData',
    ($] >= 5.005 ?
        (
            ABSTRACT => 'Provides quick CGI forms for database tables',
            AUTHOR   => 'Mark Summerfield <summer@perlpress.com>',
        ) : () ),
    'LIBS'         => [''],   # e.g., '-lm'
    'DEFINE'       => '',     # e.g., '-DHAVE_SOMETHING'
    'INC'          => '',     # e.g., '-I/usr/include/other'
    'dist'         => { COMPRESS => "gzip -9", SUFFIX => "gz" }
) ;
