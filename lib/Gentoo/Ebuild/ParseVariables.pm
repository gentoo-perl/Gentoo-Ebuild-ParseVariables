use strict;
use warnings;

package Gentoo::Ebuild::ParseVariables;
# ABSTRACT: Query variables in ebuilds

BEGIN {
	$Gentoo::Ebuild::ParseVariables::VERSION = '0.0.1';
}

use Sub::Exporter -setup => { exports => [qw( gentoo_ebuild_var )] };
use Shell::EnvImporter;
use File::ShareDir;
#use Data::Dumper;

sub _mandatory_variable {
    my $variable = shift;
    my $mandatory = {
	DESCRIPTION => 1,
	HOMEPAGE => 1,
	IUSE => 1,
	KEYWORDS => 1,
	SLOT => 1,
	SRC_URI => 1,
	LICENSE => 1,
    };
    return $mandatory->{$variable};
}

sub gentoo_ebuild_var {

	my ( $ebuild, $ebuild_vars, $portdir ) = @_;
	$ebuild_vars ||= _ebuild_vars();
	$portdir     ||= "/usr/portage";

	my $fixed_eclasses = File::ShareDir::module_dir('Gentoo::Ebuild::ParseVariables');
	my $ebuildsh       = File::ShareDir::module_file('Gentoo::Ebuild::ParseVariables','ebuild.sh');

	$ebuild =~ qr,(?<repo>.+)/(?<category>[^/]+)/(?<package>[^/]+)/\g{package}-(?<version>.+)\.ebuild,;
	my $repo     = $+{repo};
	my $category = $+{category};
	my $pn       = $+{package};
	my $pvr      = $+{version};
	(my $pv       = $pvr )=~ s/-r[0-9]+$//;
	my $pr = ( $pvr =~ m{.*-(r[0-9]+)$} )? $1 : "r0";

	my $command;
	$command.="unset $_; " for ( @{$ebuild_vars} );
	$command.="export ";
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
	$command.="; ";
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
		print "* $category/$pn-$pvr : $var not defined\n" if not defined $ENV{$var} and _mandatory_variable($var);
		$retval->{$var} = _sanitize($ENV{$var}) if defined $ENV{$var};
	}
	$sourcer->restore_env();
	return $retval;
}

sub _sanitize {
	my ($v) = @_;
	$v=~s/^\$'(.*)'$/$1/m;
	$v=~s/^'(.*)'$/$1/m;
	$v=~s/'\\''/'/g;
	$v=~s/\\'/'/g;
	$v=~s/\\[tn]/ /g;
	$v=~s/^\s+//;
	$v=~s/\s+$//;
	$v=~s/\s{2,}/ /g;
	return $v;
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
		CATEGORY
		P
		PN
		PV
		PVR
		PF
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

		DEPEND
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
