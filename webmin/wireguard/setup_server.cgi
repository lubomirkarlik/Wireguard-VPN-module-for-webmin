#!/usr/bin/perl
# setup_server.cgi
# Vykoná prvotné nastavenie servera a zobrazí výsledok krok za krokom

require './wireguard-lib.pl';
&error_setup($text{'setup_err'});
&ReadParse();

my %o;
foreach my $k ("endpoint", "port", "nic", "v4", "v6") {
	$o{$k} = $in{$k};
	$o{$k} = "" if (!defined($o{$k}));
	$o{$k} =~ s/^\s+//;
	$o{$k} =~ s/\s+$//;
	}
$o{'install'} = $in{'install'} ? 1 : 0;
$o{'firewall'} = $in{'firewall'} ? 1 : 0;

my $err = &validate_setup(\%o);
&error($err) if ($err);

# Existujúci server: nové nastavenie zahodí všetkých klientov, treba potvrdenie
if (-r &conf_file() && !$in{'confirm'}) {
	&ui_print_header(undef, $text{'setup_title'}, "");
	print &text('setup_confirm_exists', "<tt>".&html_escape(&conf_file())."</tt>"),"<p>\n";
	print &ui_form_start("setup_server.cgi", "post");
	foreach my $k (keys %o) {
		print &ui_hidden($k, $o{$k});
		}
	print &ui_hidden("confirm", 1);
	print &ui_form_end([ [ "go", $text{'setup_confirm_ok'} ] ]);
	&ui_print_footer("", $text{'index_return'});
	exit;
	}

&ui_print_header(undef, $text{'setup_title'}, "");
my ($steps, $ok) = &setup_server(\%o);
&webmin_log("setup", "server", $o{'nic'});

my %mark = ( 'ok' => "<b style='color:#2a8a2a'>[OK]</b>",
	     'warn' => "<b style='color:#c07000'>[!]</b>",
	     'err' => "<b style='color:#b22222'>[$text{'setup_error'}]</b>" );
print "<ul style='list-style:none;padding-left:0'>\n";
foreach my $s (@$steps) {
	print "<li>$mark{$s->[0]} $s->[1]</li>\n";
	}
print "</ul>\n";

if ($ok) {
	my $nas = &nic_ip($o{'nic'}) || "?";
	print "<p><b>$text{'setup_done'}</b></p>\n";
	print "<p><b>$text{'setup_manual_title'}</b></p><ol>\n";
	print "<li>",&text('setup_manual_pf', "<tt>$o{'port'}/udp</tt>",
			  "<tt>".&html_escape($nas)."</tt>"),"</li>\n";
	print "<li>$text{'setup_manual_ip'}</li>\n";
	print "<li>$text{'setup_manual_ddns'}</li>\n";
	print "</ol>\n";
	print "<p>$text{'setup_next'}</p>\n";
	}
else {
	print "<p><b>$text{'setup_failed'}</b></p>\n";
	}

&ui_print_footer("", $text{'index_return'});
