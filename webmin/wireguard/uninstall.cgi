#!/usr/bin/perl
# uninstall.cgi
# Odinštaluje WireGuard a bezpečne upraví súbory. Vyžaduje napísanie názvu rozhrania.

require './wireguard-lib.pl';
&error_setup($text{'uninst_err'});
&ReadParse();

&error($text{'uninst_confirm_err'}) if ($in{'confirm_text'} ne $config{'interface'});

my %o = map { $_ => ($in{$_} ? 1 : 0) }
	("backup", "ufw", "sysctl", "remove_conf", "remove_packages");
my ($steps, $ok) = &uninstall_wireguard(\%o);
&webmin_log("uninstall", "server", $config{'interface'});

&ui_print_header(undef, $text{'uninst_title'}, "");
my %mark = ( 'ok' => "<b style='color:#2a8a2a'>[OK]</b>",
	     'warn' => "<b style='color:#c07000'>[!]</b>",
	     'err' => "<b style='color:#b22222'>[$text{'setup_error'}]</b>" );
print "<ul style='list-style:none;padding-left:0'>\n";
foreach my $s (@$steps) {
	print "<li>$mark{$s->[0]} $s->[1]</li>\n";
	}
print "</ul>\n";
print "<p><b>".($ok ? $text{'uninst_done'} : $text{'uninst_failed'})."</b></p>\n";
if ($ok) {
	print "<p>$text{'uninst_note'}</p>\n";
	}
&ui_print_footer("", $text{'index_return'});
