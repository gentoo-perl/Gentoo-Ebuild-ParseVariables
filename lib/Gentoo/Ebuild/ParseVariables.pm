use strict;
use warnings;

package Gentoo::Ebuild::ParseVariables;
# ABSTRACT: Query variables in ebuilds

BEGIN {
	$Gentoo::Ebuild::ParseVariables::VERSION = '0.0.1';
}

use Sub::Exporter -setup => { exports => [qw( gentoo_ebuild_var )] };
use Shell::EnvImporter;
use File::Spec;
#use Data::Dumper;

sub gentoo_ebuild_var {

	my ( $ebuild, $ebuild_vars, $portdir ) = @_;
	$ebuild_vars ||= _ebuild_vars();
	$portdir     ||= "/usr/portage";

	my $fixed_eclasses = _installed_file_for_module('Gentoo::Ebuild::ParseVariables')."ParseVariables";
	my $ebuildsh       = _installed_file_for_module('Gentoo::Ebuild::ParseVariables')."ParseVariables/ebuild.sh";

	$ebuild =~ qr,(?<repo>.+)/(?<category>[^/]+)/(?<package>[^/]+)/\g{package}-(?<version>.+)\.ebuild,;
	my $repo     = $+{repo};
	my $category = $+{category};
	my $pn       = $+{package};
	my $pvr      = $+{version};
	(my $pv       = $pvr )=~ s/-r[0-9]+$//;
	my $pr = ( $pvr =~ m{.*-(r[0-9]+)$} )? $1 : "r0";

	my $command;
	$command.="unset $_; " for ( @{$ebuild_vars} );
	$command.="EBUILD=$ebuild ";
	$command.="ECLASSDIR=$portdir/eclass ";
	$command.="PORTDIR_OVERLAY='$repo $fixed_eclasses' ";
	$command.="CATEGORY=$category ";
	$command.="PN=$pn ";
	$command.="PV=$pv ";
	$command.="PVR=$pvr ";
	$command.="PF=$pn-$pvr ";
	$command.="PR=$pr ";
	$command.="P=$pn-$pv ";
	$command.="source $ebuildsh ";

	my $sourcer  = Shell::EnvImporter->new(
		shell       => 'bash',
		command     => $command,
		debuglevel  => 0,
		auto_run    => 0,
		auto_import => 0,
	);

	$sourcer->shellobj->envcmd('set');
	$sourcer->run;
	$sourcer->env_import($ebuild_vars);

	my $retval= {};
	for my $var ( @{$ebuild_vars} ) {
		$retval->{$var} = _sanitize($ENV{$var}) if defined $ENV{$var};
	}
	$sourcer->restore_env();
	return $retval;
}

sub _sanitize {
	my ($var) = @_;
	$var =~ s/^\$//g;
	$var =~ s/^(')(.*)\1$/$2/g;
	$var =~ s/(')(.*)\1/$2/g;
	$var =~ s/\\[nt]/ /g;
	$var =~ s/\\'/'/g;
	$var =~ s/'+/'/g;
	$var =~ s/ +/ /g;
	$var =~ s/^ +//g;
	$var =~ s/ +$//g;
	return $var;
}

sub _installed_file_for_module {
    my $prereq = shift;

    my $file = "$prereq.pm";
    $file =~ s{::}{/}g;

    for my $dir (@INC) {
        my $tmp = File::Spec->catfile($dir, $file);
        return (File::Spec->splitpath($tmp))[1] if ( -r $tmp );
    }
}


sub _ebuild_vars {
	return [ qw(
		EAPI

		MODULE_AUTHOR
		MODULE_SECTION
		MODULE_VERSION
		MODULE_A
		MODULE_EXT
		MODULE_PN
		MODULE_PV
		MY_P
		MY_PN
		MY_PV

		DESCRIPTION
		HOMEPAGE
		SRC_URI

		LICENSE
		SLOT
		KEYWORDS
		IUSE
		OIUSE

		DEPEND
		ODEPEND
		EDEPEND
		RDEPEND
		PDEPEND

		SRC_TEST
		INHERITED
		DEFINED_PHASES
		RESTRICT
		REQUIRED_USE
		) ];
};

1;
