#!/usr/bin/perl
# index.cgi
# Prehľad servera a klientov WireGuard

require './wireguard-lib.pl';
&ReadParse();
&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);

if (!&has_command($config{'wg'}) || !-r &conf_file()) {
	if (!&has_command($config{'wg'})) {
		print &text('index_ewg', "<tt>$config{'wg'}</tt>"),"<p>\n";
		}
	if (!-r &conf_file()) {
		print &text('index_econf', "<tt>".&conf_file()."</tt>"),"<p>\n";
		}
	print &install_status_table(&get_install_status());
	print &ui_buttons_start();
	print &ui_buttons_row("setup.cgi", $text{'index_setup'}, $text{'index_setup_d'});
	print &ui_buttons_row("install.cgi", $text{'index_install'}, $text{'index_install_d'});
	print &ui_buttons_end();
	&ui_print_footer("/", $text{'index'});
	exit;
	}
my $srv = &get_server();
if (!$srv) {
	print &text('index_ebad', "<tt>".&conf_file()."</tt>"),"<p>\n";
	print "<a href='setup.cgi'>$text{'index_recreate'}</a><p>\n";
	&ui_print_footer("/", $text{'index'});
	exit;
	}
my ($head, $peers) = &parse_conf();
my $status = &get_status();
my $up = &interface_up();

# Server
print &ui_table_start($text{'index_server'}, "width=100%", 2);
print &ui_table_row($text{'index_if'}, "<tt>$config{'interface'}</tt>");
print &ui_table_row($text{'index_state'},
	$up ? "<b style='color:#2a8a2a'>$text{'index_up'}</b>"
	    : "<b style='color:#b22222'>$text{'index_down'}</b>");
print &ui_table_row($text{'index_boot'},
	&service_enabled() ? $text{'index_yes'} : $text{'index_no'});
print &ui_table_row($text{'index_addr'}, "<tt>".&html_escape($srv->{'address'})."</tt>");
print &ui_table_row($text{'index_port'}, "<tt>".$srv->{'port'}."/udp</tt>");
print &ui_table_row($text{'index_pub'}, "<tt>".&html_escape($srv->{'pubkey'})."</tt>");
print &ui_table_end();

print &ui_buttons_start();
print &ui_buttons_row("service.cgi", $text{'index_start'}, $text{'index_start_d'},
		      &ui_hidden("action", "start"));
print &ui_buttons_row("service.cgi", $text{'index_stop'}, $text{'index_stop_d'},
		      &ui_hidden("action", "stop"));
print &ui_buttons_row("service.cgi", $text{'index_restart'}, $text{'index_restart_d'},
		      &ui_hidden("action", "restart"));
print &ui_buttons_row("service.cgi", $text{'index_enable'}, $text{'index_enable_d'},
		      &ui_hidden("action", "enable"));
print &ui_buttons_row("service.cgi", $text{'index_disable'}, $text{'index_disable_d'},
		      &ui_hidden("action", "disable"));
print &ui_buttons_row("edit_server.cgi", $text{'index_edit'}, $text{'index_edit_d'});
print &ui_buttons_row("install.cgi", $text{'index_install'}, $text{'index_install_d'});
print &ui_buttons_end();

# WAN
print &ui_form_start("save_endpoint.cgi", "post");
print &ui_table_start($text{'index_wan'}, "width=100%", 2);
print &ui_table_row($text{'index_endpoint'},
	&ui_textbox("endpoint", &get_endpoint(), 40)."<br>".
	"<small>".$text{'index_endpoint_d'}."</small>");
print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

# Klienti
print &ui_hr();
print "<h3>$text{'index_clients'}</h3>\n";
if (@$peers) {
	print &ui_columns_start([ $text{'index_cname'}, $text{'index_cip'},
				  $text{'index_chs'}, $text{'index_cxfer'},
				  $text{'index_cact'} ], 100);
	foreach my $p (sort { ($a->{'octet'} || 0) <=> ($b->{'octet'} || 0) } @$peers) {
		my $st = $status->{$p->{'pubkey'}} || {};
		my $xfer = $st->{'rx'} || $st->{'tx'} ?
			"&darr; ".&human_bytes($st->{'rx'})." &uarr; ".&human_bytes($st->{'tx'}) :
			"-";
		my $act = defined($p->{'octet'}) ?
		    "<a href='add_client.cgi?name=".&urlize($p->{'name'}).
			"&octet=$p->{'octet'}'>$text{'index_regen'}</a> | ".
		    "<a href='delete_client.cgi?octet=$p->{'octet'}'>$text{'index_delete'}</a>" :
		    "";
		print &ui_columns_row([ &html_escape($p->{'name'}),
					"<tt>".&html_escape($p->{'allowed'})."</tt>",
					&human_age($st->{'handshake'}),
					$xfer, $act ]);
		}
	print &ui_columns_end();
	}
else {
	print "<i>$text{'index_noclients'}</i><p>\n";
	}

# Pridanie klienta
my $suggest = &next_free_octet($peers);
print &ui_form_start("save_client.cgi", "post");
print &ui_table_start($text{'index_add'}, "width=100%", 2);
print &ui_table_row($text{'add_name'}, &ui_textbox("name", "", 25));
print &ui_table_row($text{'add_ip'},
	"<tt>".$srv->{'v4net'}.".</tt>".&ui_textbox("octet", $suggest, 4));
print &ui_table_end();
print &ui_form_end([ [ "create", $text{'add_create'} ] ]);

print &ui_hr();
print "<a href='setup.cgi'>$text{'index_recreate'}</a>\n";

&ui_print_footer("/", $text{'index'});
