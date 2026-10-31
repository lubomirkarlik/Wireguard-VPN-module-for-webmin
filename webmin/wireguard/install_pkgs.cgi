#!/usr/bin/perl
# install_pkgs.cgi
# Doinštaluje chýbajúce balíky (wireguard, qrencode, iptables)

require './wireguard-lib.pl';
&error_setup($text{'inst_install_err'});
&ReadParse();

my ($err, $inst) = &install_packages();
&error($err) if ($err);
&webmin_log("install", "packages", join(",", @$inst));

&ui_print_header(undef, $text{'inst_title'}, "");
if (@$inst) {
	print "<b style='color:#2a8a2a'>[OK]</b> ",
	      &text('setup_pkgs', "<tt>".join(" ", @$inst)."</tt>"),"<p>\n";
	}
else {
	print "<b style='color:#2a8a2a'>[OK]</b> $text{'setup_pkgs_ok'}<p>\n";
	}
&ui_print_footer("install.cgi", $text{'inst_title'});
