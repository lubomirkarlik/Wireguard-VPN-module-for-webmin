# wireguard-lib.pl
# Spoločné funkcie modulu WireGuard VPN. Číta a zapisuje wg0.conf natívne,
# rovnakým formátom ako skripty regen-wg.sh a add-wg-client.sh.

BEGIN { push(@INC, ".."); };
use WebminCore;
use MIME::Base64 qw(encode_base64);
use POSIX qw(strftime);
&init_config();

# conf_file()
# Cesta k wg0.conf
sub conf_file
{
return $config{'conf_dir'}."/".$config{'interface'}.".conf";
}

# endpoint_file()
# Súbor s verejnou adresou (WAN), zdieľaný so skriptami
sub endpoint_file
{
return $config{'conf_dir'}."/.endpoint";
}

# get_endpoint()
# Vráti uložený WAN alebo undef
sub get_endpoint
{
my $f = &endpoint_file();
return undef if (!-r $f);
my $e = &read_file_contents($f);
$e =~ s/^\s+//;
$e =~ s/\s+$//;
return $e eq "" ? undef : $e;
}

# save_endpoint(endpoint)
sub save_endpoint
{
my ($e) = @_;
my $f = &endpoint_file();
&lock_file($f);
&open_tempfile(EP, ">$f");
&print_tempfile(EP, "$e\n");
&close_tempfile(EP);
chmod(0600, $f);
&unlock_file($f);
}

# run_cmd(command)
# Vráti (exit, stdout, stderr)
sub run_cmd
{
my ($cmd) = @_;
my ($out, $err);
my $rc = &execute_command($cmd, undef, \$out, \$err);
return ($rc, $out, $err);
}

# gen_key(command, label)
# Spustí príkaz a vráti jeho výstup bez bielych znakov. Príkaz sa v chybe
# nevypisuje, môže obsahovať kľúč.
sub gen_key
{
my ($cmd, $label) = @_;
my ($rc, $out, $err) = &run_cmd($cmd);
$out =~ s/\s+//g;
if ($rc || $out eq "") {
	&error(&text('err_cmd', "<tt>".&html_escape($label)."</tt>",
		     &html_escape($err)));
	}
return $out;
}

# parse_conf_text(text)
# Rozdelí konfiguráciu na bloky oddelené prázdnym riadkom. Vráti (\@head,
# \@peers): head sú bloky mimo [Peer] (text), peers sú hashe so záznamom klienta.
sub parse_conf_text
{
my ($text) = @_;
$text = "" if (!defined($text));
$text =~ s/\r//g;
my (@head, @peers);
foreach my $b (split(/\n[ \t]*\n/, $text)) {
	$b =~ s/^\s*\n+//;
	$b =~ s/\s+$//;
	next if ($b !~ /\S/);
	if ($b =~ /^\s*\[Peer\]/m) {
		my %p = ( 'text' => $b );
		($p{'name'}) = $b =~ /^###\s*Client\s+(.*?)\s*$/m;
		($p{'pubkey'}) = $b =~ /^\s*PublicKey\s*=\s*(\S+)/m;
		($p{'allowed'}) = $b =~ /^\s*AllowedIPs\s*=\s*(.+?)\s*$/m;
		my ($first) = split(/\s*,\s*/, $p{'allowed'} || "");
		$first =~ s/\/\d+$// if (defined($first));
		$p{'ip'} = $first;
		($p{'octet'}) = $first =~ /\.(\d+)$/ if ($first);
		$p{'name'} = "?" if (!defined($p{'name'}) || $p{'name'} eq "");
		push(@peers, \%p);
		}
	else {
		push(@head, $b);
		}
	}
return (\@head, \@peers);
}

# parse_conf()
sub parse_conf
{
my $f = &conf_file();
return &parse_conf_text(-r $f ? &read_file_contents($f) : "");
}

# build_conf_text(\@head, \@peers)
sub build_conf_text
{
my ($head, $peers) = @_;
return join("\n\n", @$head, map { $_->{'text'} } @$peers)."\n";
}

# write_conf(\@head, \@peers)
# Zapíše wg0.conf (práva 0600) a vytvorí zálohu predošlej verzie
sub write_conf
{
my ($head, $peers) = @_;
my $f = &conf_file();
&lock_file($f);
if (-r $f) {
	my $bak = $f.".bak.".strftime("%Y%m%d-%H%M%S", localtime());
	&copy_source_dest($f, $bak);
	chmod(0600, $bak);
	}
&open_tempfile(CONF, ">$f");
&print_tempfile(CONF, &build_conf_text($head, $peers));
&close_tempfile(CONF);
chmod(0600, $f);
&unlock_file($f);
}

# get_server()
# Údaje o serveri z [Interface] alebo undef, ak je konfigurácia neplatná
sub get_server
{
my ($head, $peers) = &parse_conf();
my $t = join("\n", @$head);
my %s;
($s{'address'}) = $t =~ /^\s*Address\s*=\s*(.+?)\s*$/m;
($s{'port'}) = $t =~ /^\s*ListenPort\s*=\s*(\d+)/m;
($s{'privkey'}) = $t =~ /^\s*PrivateKey\s*=\s*(\S+)/m;
return undef if (!$s{'address'} || !$s{'port'} || !$s{'privkey'});
my ($v4, $v6) = split(/\s*,\s*/, $s{'address'});
if ($v4 =~ /^(\d+\.\d+\.\d+)\.\d+(?:\/\d+)?$/) {
	$s{'v4net'} = $1;
	}
else {
	return undef;
	}
if ($v6 && $v6 =~ /^(.+?)::/) {
	$s{'v6base'} = $1;
	}
$s{'pubkey'} = &gen_key("printf %s ".quotemeta($s{'privkey'})." | ".
			$config{'wg'}." pubkey", "wg pubkey");
return \%s;
}

# interface_up()
sub interface_up
{
my ($rc, $out) = &run_cmd($config{'wg'}." show interfaces");
return 0 if ($rc);
return (grep { $_ eq $config{'interface'} } split(/\s+/, $out)) ? 1 : 0;
}

# get_status()
# Hash verejný kľúč -> stav (handshake, rx, tx, endpoint) z `wg show dump`
sub get_status
{
my %st;
my ($rc, $out) = &run_cmd($config{'wg'}." show ".
			  quotemeta($config{'interface'})." dump");
return \%st if ($rc || !$out);
my @l = split(/\n/, $out);
shift(@l);
foreach my $l (@l) {
	my ($pub, $psk, $ep, $allowed, $hs, $rx, $tx) = split(/\t/, $l);
	next if (!$pub);
	$st{$pub} = { 'endpoint' => $ep, 'handshake' => $hs,
		      'rx' => $rx, 'tx' => $tx };
	}
return \%st;
}

# service_name()
sub service_name
{
return "wg-quick\@".$config{'interface'};
}

# service_enabled()
sub service_enabled
{
my ($rc, $out) = &run_cmd("systemctl is-enabled ".quotemeta(&service_name()));
return $rc == 0 && $out =~ /enabled/ ? 1 : 0;
}

# service_action(action)
# start, stop, restart, enable, disable. Vráti chybový text alebo undef.
sub service_action
{
my ($a) = @_;
return "?" if ($a !~ /^(start|stop|restart|enable|disable)$/);
my ($rc, $out, $err) = &run_cmd("systemctl $a ".quotemeta(&service_name()));
return $rc ? ($err || $out || "systemctl $a failed") : undef;
}

# apply_conf()
# Načíta zmenu do bežiaceho tunela bez prerušenia ostatných klientov.
# Vráti chybový text alebo undef (aj keď tunel nebeží).
sub apply_conf
{
return undef if (!&interface_up());
my $tmp = &transname();
my ($rc, $out, $err) = &run_cmd($config{'wg_quick'}." strip ".
				quotemeta(&conf_file())." > ".quotemeta($tmp));
if ($rc) {
	&unlink_file($tmp);
	return $err || $out || "wg-quick strip failed";
	}
($rc, $out, $err) = &run_cmd($config{'wg'}." syncconf ".
			     quotemeta($config{'interface'})." ".quotemeta($tmp));
&unlink_file($tmp);
return $rc ? ($err || $out || "wg syncconf failed") : undef;
}

# next_free_octet(\@peers)
sub next_free_octet
{
my ($peers) = @_;
my %used = map { $_->{'octet'} => 1 } grep { defined($_->{'octet'}) } @$peers;
for(my $i=2; $i<=254; $i++) {
	return $i if (!$used{$i});
	}
return undef;
}

# find_peer(\@peers, octet)
sub find_peer
{
my ($peers, $octet) = @_;
foreach my $p (@$peers) {
	return $p if (defined($p->{'octet'}) && $p->{'octet'} == $octet);
	}
return undef;
}

# validate_client(name, octet, \@peers)
# Vráti chybový text alebo undef
sub validate_client
{
my ($name, $octet, $peers) = @_;
return $text{'err_name'} if ($name !~ /^[A-Za-z0-9_-]+$/);
return $text{'err_octet'} if ($octet !~ /^\d+$/ || $octet < 2 || $octet > 254);
foreach my $p (@$peers) {
	next if (defined($p->{'octet'}) && $p->{'octet'} == $octet);
	return &text('err_dupname', "<tt>".&html_escape($name)."</tt>")
		if ($p->{'name'} eq $name);
	}
return undef;
}

# create_client(name, octet)
# Vygeneruje kľúče, pridá (alebo nahradí) peera, uloží a načíta konfiguráciu.
# Vráti hash (conf, ip, name, warn). Súkromný kľúč sa nikam neukladá.
sub create_client
{
my ($name, $octet) = @_;
my $srv = &get_server();
&error($text{'err_server'}) if (!$srv);
my $endpoint = &get_endpoint();
&error($text{'err_noendpoint'}) if (!$endpoint);
my ($head, $peers) = &parse_conf();
my $err = &validate_client($name, $octet, $peers);
&error($err) if ($err);
my ($lan, $dns) = &client_network($head);
&error($text{'err_lan'}) if ($lan eq "");

my $ip = $srv->{'v4net'}.".".$octet;
my $key = &gen_key($config{'wg'}." genkey", "wg genkey");
my $pub = &gen_key("printf %s ".quotemeta($key)." | ".$config{'wg'}." pubkey",
		   "wg pubkey");
my $psk = &gen_key($config{'wg'}." genpsk", "wg genpsk");

my $allowed = "$ip/32";
my $addr = "$ip/32";
if ($srv->{'v6base'}) {
	$allowed .= ",".$srv->{'v6base'}."::$octet/128";
	$addr .= ",".$srv->{'v6base'}."::$octet/128";
	}

my $peer = "### Client $name\n[Peer]\nPublicKey = $pub\n".
	   "PresharedKey = $psk\nAllowedIPs = $allowed";
my @new = grep { !(defined($_->{'octet'}) && $_->{'octet'} == $octet) } @$peers;
push(@new, { 'name' => $name, 'text' => $peer, 'ip' => $ip,
	     'octet' => $octet, 'pubkey' => $pub, 'allowed' => $allowed });
&write_conf($head, \@new);
my $warn = &apply_conf();

my $conf = "[Interface]\nPrivateKey = $key\nAddress = $addr\n";
$conf .= "DNS = $dns\n" if ($dns ne "");
$conf .= "\n[Peer]\nPublicKey = ".$srv->{'pubkey'}."\nPresharedKey = $psk\n".
	 "Endpoint = $endpoint:".$srv->{'port'}."\n".
	 "AllowedIPs = $lan, ".$srv->{'v4net'}.".0/24\n".
	 "PersistentKeepalive = 25\n";
return { 'conf' => $conf, 'ip' => $ip, 'name' => $name, 'warn' => $warn };
}

# delete_client(octet)
# Vráti chybový text pri neúspešnom načítaní konfigurácie alebo undef
sub delete_client
{
my ($octet) = @_;
my ($head, $peers) = &parse_conf();
my @new = grep { !(defined($_->{'octet'}) && $_->{'octet'} == $octet) } @$peers;
&error($text{'err_nopeer'}) if (@new == @$peers);
&write_conf($head, \@new);
return &apply_conf();
}

# write_private_file(path, data)
sub write_private_file
{
my ($f, $data) = @_;
my $old = umask(077);
open(my $fh, ">", $f) || &error(&text('err_write', &html_escape($f), $!));
binmode($fh);
print $fh $data;
close($fh);
umask($old);
}

# qr_png_base64(text)
# QR kód ako base64 PNG (na vloženie cez data: URI)
sub qr_png_base64
{
my ($conf) = @_;
my $in = &transname();
my $png = &transname();
&write_private_file($in, $conf);
my ($rc, $out, $err) = &run_cmd($config{'qrencode'}.
	" -t PNG -l L -m 2 -s 6 -o ".quotemeta($png)." < ".quotemeta($in));
&unlink_file($in);
if ($rc) {
	&unlink_file($png);
	return undef;
	}
open(my $fh, "<", $png) || return undef;
binmode($fh);
local $/ = undef;
my $data = <$fh>;
close($fh);
&unlink_file($png);
return encode_base64($data, "");
}

# human_age(seconds)
sub human_age
{
my ($s) = @_;
return $text{'index_never'} if (!$s);
my $d = time() - $s;
$d = 0 if ($d < 0);
return &text('age_s', $d) if ($d < 60);
return &text('age_m', int($d/60)) if ($d < 3600);
return &text('age_h', int($d/3600)) if ($d < 86400);
return &text('age_d', int($d/86400));
}

# human_bytes(n)
sub human_bytes
{
my ($n) = @_;
$n ||= 0;
return &nice_size($n);
}

# detect_nic()
# Sieťová karta predvolenej trasy (do LAN) alebo prázdny reťazec
sub detect_nic
{
my ($rc, $out) = &run_cmd("ip -4 route show default");
return $1 if ($out =~ /\bdev\s+(\S+)/);
return "";
}

# nic_ip(nic)
# Prvá globálna IPv4 adresa karty (bez masky) alebo prázdny reťazec
sub nic_ip
{
my ($nic) = @_;
my ($rc, $out) = &run_cmd("ip -4 -o addr show dev ".quotemeta($nic)." scope global");
return $1 if ($out =~ /\binet\s+(\d+\.\d+\.\d+\.\d+)/);
return "";
}

# detect_lan(nic)
# Podsieť priamo pripojená na kartu (napr. 192.168.1.0/24) alebo prázdny reťazec
sub detect_lan
{
my ($nic) = @_;
my ($rc, $out) = &run_cmd("ip -4 route show dev ".quotemeta($nic).
			  " proto kernel scope link");
return $1 if ($out =~ /^(\d+\.\d+\.\d+\.\d+\/\d+)\s/m);
return "";
}

# detect_gateway(nic)
# Predvolená brána na karte alebo prázdny reťazec
sub detect_gateway
{
my ($nic) = @_;
my ($rc, $out) = &run_cmd("ip -4 route show default dev ".quotemeta($nic));
return $1 if ($out =~ /\bvia\s+(\d+\.\d+\.\d+\.\d+)/);
return "";
}

# client_network(\@head)
# LAN a DNS pre klientov. Hodnota "auto" sa zistí zo sieťovej karty servera.
# Vráti (lan, dns); prázdne lan znamená neúspešné zistenie, prázdne dns je bez DNS.
sub client_network
{
my ($head) = @_;
my ($lan, $dns) = ($config{'lan'}, $config{'dns'});
return ($lan, $dns) if ($lan ne "auto" && $dns ne "auto");
my ($nic) = join("\n", @$head) =~ /^\s*PostUp\s*=\s*iptables\s+-t\s+nat\s+-A\s+POSTROUTING\s+-o\s+(\S+)/m;
$nic ||= &detect_nic();
$lan = &detect_lan($nic) if ($lan eq "auto");
$dns = &detect_gateway($nic) if ($dns eq "auto");
return ($lan, $dns);
}

# validate_setup(\%opts)
# Hodnoty sa dostanú do PostUp príkazov (spúšťajú sa ako root), preto prísna
# validácia. Vráti chybový text alebo undef.
sub validate_setup
{
my ($o) = @_;
return $text{'err_endpoint'} if (defined($o->{'endpoint'}) &&
				 $o->{'endpoint'} !~ /^[A-Za-z0-9._:\[\]-]+$/);
return $text{'err_port'} if ($o->{'port'} !~ /^\d+$/ || $o->{'port'} < 1 ||
			      $o->{'port'} > 65535);
return $text{'err_nic'} if ($o->{'nic'} !~ /^[A-Za-z0-9_.:-]+$/);
if ($o->{'v4'} !~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/(\d{1,2})$/ ||
    $1 > 255 || $2 > 255 || $3 > 255 || $4 > 255 || $5 > 32) {
	return $text{'err_v4'};
	}
if ($o->{'v6'} ne "" &&
    ($o->{'v6'} !~ /^[0-9a-fA-F:]+\/(\d{1,3})$/ || $1 > 128 ||
     $o->{'v6'} !~ /::/)) {
	return $text{'err_v6'};
	}
return undef;
}

# build_server_conf(\%opts, privkey)
# Text bloku [Interface] (bez prázdnych riadkov), rovnaký ako vytvára regen-wg.sh
sub build_server_conf
{
my ($o, $key) = @_;
my $if = $config{'interface'};
my ($port, $nic) = ($o->{'port'}, $o->{'nic'});
my $addr = $o->{'v4'};
$addr .= ",".$o->{'v6'} if ($o->{'v6'} ne "");
my (@up, @down);
foreach my $r ([ "INPUT -p udp --dport $port -j ACCEPT" ],
	       [ "FORWARD -i $nic -o $if -j ACCEPT" ],
	       [ "FORWARD -i $if -j ACCEPT" ]) {
	push(@up, "iptables -I $r->[0]");
	push(@down, "iptables -D $r->[0]");
	}
push(@up, "iptables -t nat -A POSTROUTING -o $nic -j MASQUERADE");
push(@down, "iptables -t nat -D POSTROUTING -o $nic -j MASQUERADE");
if ($o->{'v6'} ne "") {
	push(@up, "ip6tables -I FORWARD -i $if -j ACCEPT");
	push(@down, "ip6tables -D FORWARD -i $if -j ACCEPT");
	push(@up, "ip6tables -t nat -A POSTROUTING -o $nic -j MASQUERADE");
	push(@down, "ip6tables -t nat -D POSTROUTING -o $nic -j MASQUERADE");
	}
return "[Interface]\nAddress = $addr\nListenPort = $port\nPrivateKey = $key\n".
       join("", map { "PostUp = $_\n" } @up).
       join("", map { "PostDown = $_\n" } @down);
}

# setup_server(\%opts)
# Prvotné nastavenie servera ako regen-wg.sh: balíky, wg0.conf, forwarding,
# firewall (ufw), služba a kontroly. Vráti (\@steps, $ok); steps sú
# [ 'ok'|'warn'|'err', text ]. Pri chybe sa skončí.
sub setup_server
{
my ($o) = @_;
my @s;
my $if = $config{'interface'};
my $svc = &service_name();
my ($rc, $out, $err);
my $fail = sub { push(@s, [ 'err', $_[0] ]); return (\@s, 0); };

# 1. Balíky
my @need = &missing_packages();
if (@need) {
	return &$fail(&text('setup_nopkg', "<tt>".join(" ", @need)."</tt>"))
		if (!$o->{'install'});
	my ($ierr, $inst) = &install_packages();
	return &$fail($ierr) if ($ierr);
	push(@s, [ 'ok', &text('setup_pkgs', "<tt>".join(" ", @$inst)."</tt>") ]);
	}
else {
	push(@s, [ 'ok', $text{'setup_pkgs_ok'} ]);
	}

# 2. wg0.conf (starý sa zálohuje) a WAN
&make_dir($config{'conf_dir'}, 0700) if (!-d $config{'conf_dir'});
my $key = &gen_key($config{'wg'}." genkey", "wg genkey");
&write_conf([ &build_server_conf($o, $key) ], []);
&save_endpoint($o->{'endpoint'});
push(@s, [ 'ok', &text('setup_conf', "<tt>".&html_escape(&conf_file())."</tt>") ]);

# 3. IP forwarding
my $sf = $config{'sysctl_file'};
&lock_file($sf);
&open_tempfile(SYSCTL, ">$sf");
&print_tempfile(SYSCTL, "net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n");
&close_tempfile(SYSCTL);
&unlock_file($sf);
($rc, $out, $err) = &run_cmd("sysctl -p ".quotemeta($sf));
push(@s, $rc ? [ 'warn', &text('setup_sysctl_err', &html_escape($err || $out)) ]
	     : [ 'ok', $text{'setup_sysctl'} ]);

# 4. Firewall
if ($o->{'firewall'}) {
	my $ufw_active = 0;
	if (&has_command("ufw")) {
		($rc, $out) = &run_cmd("ufw status");
		$ufw_active = 1 if ($out =~ /Status:\s*active/);
		}
	if ($ufw_active) {
		($rc, $out, $err) = &run_cmd("ufw allow ".quotemeta($o->{'port'}."/udp").
					     " comment WireGuard");
		push(@s, $rc ? [ 'warn', &text('setup_ufw_err', &html_escape($err || $out)) ]
			     : [ 'ok', &text('setup_ufw', "<tt>".$o->{'port'}."/udp</tt>") ]);
		my $uf = $config{'ufw_sysctl'};
		if (-f $uf) {
			my $t = &read_file_contents($uf);
			if ($t =~ s/^(net\/(?:ipv4\/ip_forward|ipv6\/conf\/(?:default|all)\/forwarding))=0/$1=1/mg) {
				&lock_file($uf);
				&open_tempfile(UFWS, ">$uf");
				&print_tempfile(UFWS, $t);
				&close_tempfile(UFWS);
				&unlock_file($uf);
				push(@s, [ 'ok', $text{'setup_ufw_sysctl'} ]);
				}
			}
		}
	else {
		push(@s, [ 'ok', $text{'setup_ufw_none'} ]);
		if (&has_command("nft")) {
			($rc, $out) = &run_cmd("nft list ruleset");
			push(@s, [ 'warn', &text('setup_nft', $o->{'port'}, $if) ])
				if ($out =~ /policy drop/);
			}
		}
	}

# 5. Služba
return &$fail(&text('setup_nosystemctl', "<tt>systemctl</tt>"))
	if (!&has_command("systemctl"));
($rc, $out, $err) = &run_cmd("systemctl enable ".quotemeta($svc));
push(@s, [ 'warn', &text('setup_enable_err', &html_escape($err || $out)) ]) if ($rc);
($rc, $out, $err) = &run_cmd("systemctl restart ".quotemeta($svc));
return &$fail(&text('setup_start_err', &html_escape($err || $out))) if ($rc);

# 6. Kontroly
my $ok = 1;
my $chk = sub {
	my ($label, $good) = @_;
	push(@s, [ $good ? 'ok' : 'err', $label ]);
	$ok = 0 if (!$good);
	};
($rc) = &run_cmd("systemctl is-active --quiet ".quotemeta($svc));
&$chk(&text('setup_chk_active', "<tt>$svc</tt>"), $rc == 0);
($rc) = &run_cmd("systemctl is-enabled --quiet ".quotemeta($svc));
&$chk($text{'setup_chk_boot'}, $rc == 0);
($rc, $out) = &run_cmd("ss -uln");
&$chk(&text('setup_chk_port', $o->{'port'}), $out =~ /:\Q$o->{'port'}\E\s/);
($rc, $out) = &run_cmd("sysctl -n net.ipv4.ip_forward");
&$chk($text{'setup_chk_fwd'}, $out =~ /^1/);
($rc) = &run_cmd("iptables -C INPUT -p udp --dport $o->{'port'} -j ACCEPT");
&$chk(&text('setup_chk_input', $o->{'port'}), $rc == 0);
($rc) = &run_cmd("iptables -t nat -C POSTROUTING -o ".quotemeta($o->{'nic'}).
		 " -j MASQUERADE");
&$chk(&text('setup_chk_nat', "<tt>".&html_escape($o->{'nic'})."</tt>"), $rc == 0);
return (\@s, $ok);
}

# missing_packages()
# Zoznam balíkov, ktoré treba doinštalovať
sub missing_packages
{
my @need;
push(@need, "wireguard") if (!&has_command($config{'wg'}));
push(@need, "qrencode") if (!&has_command($config{'qrencode'}));
push(@need, "iptables") if (!&has_command("iptables") || !&has_command("ip6tables"));
return @need;
}

# install_packages()
# Doinštaluje chýbajúce balíky cez apt. Vráti (chybový text alebo undef,
# \@nainštalované).
sub install_packages
{
my @need = &missing_packages();
return (undef, []) if (!@need);
return ($text{'setup_noapt'}, []) if (!&has_command("apt-get"));
my ($rc, $out, $err) = &run_cmd("DEBIAN_FRONTEND=noninteractive apt-get update -qq ".
	"&& DEBIAN_FRONTEND=noninteractive apt-get install -y ".join(" ", @need));
return (&text('setup_apt_err', &html_escape($err || $out)), []) if ($rc);
return (&text('setup_nopkg', "<tt>".join(" ", @need)."</tt>"), [])
	if (!&has_command($config{'wg'}));
return (undef, \@need);
}

# pkg_installed(package)
sub pkg_installed
{
my ($p) = @_;
return 0 if (!&has_command("dpkg"));
my ($rc, $out) = &run_cmd("dpkg -s ".quotemeta($p));
return ($rc == 0 && $out =~ /^Status:\s*install ok installed/m) ? 1 : 0;
}

# ufw_state()
# 'none', 'inactive' alebo 'active'
sub ufw_state
{
return "none" if (!&has_command("ufw"));
my ($rc, $out) = &run_cmd("ufw status");
return $out =~ /Status:\s*active/ ? "active" : "inactive";
}

# get_install_status()
# Stav inštalácie WireGuardu na serveri
sub get_install_status
{
my %s;
$s{'wg'} = &has_command($config{'wg'}) ? 1 : 0;
$s{'pkg_tools'} = &pkg_installed("wireguard-tools");
$s{'pkg_wireguard'} = &pkg_installed("wireguard");
$s{'qrencode'} = &has_command($config{'qrencode'}) ? 1 : 0;
$s{'iptables'} = (&has_command("iptables") && &has_command("ip6tables")) ? 1 : 0;
my ($rc) = &run_cmd("modinfo wireguard");
$s{'kernel'} = ($rc == 0 || -d "/sys/module/wireguard") ? 1 : 0;
$s{'conf'} = -r &conf_file() ? 1 : 0;
$s{'up'} = $s{'wg'} ? &interface_up() : 0;
$s{'enabled'} = &has_command("systemctl") ? &service_enabled() : 0;
$s{'ufw'} = &ufw_state();
$s{'apt'} = &has_command("apt-get") ? 1 : 0;
$s{'installed'} = ($s{'wg'} && $s{'kernel'}) ? 1 : 0;
return \%s;
}

# install_status_table(\%status)
# HTML tabuľka so stavom inštalácie
sub install_status_table
{
my ($st) = @_;
my $y = sub { $_[0] ? "<b style='color:#2a8a2a'>$text{'index_yes'}</b>"
		    : "<b style='color:#b22222'>$text{'index_no'}</b>" };
my $t = &ui_table_start($text{'inst_status'}, "width=100%", 2);
$t .= &ui_table_row($text{'inst_wg'}, &$y($st->{'wg'}));
$t .= &ui_table_row($text{'inst_pkgs'},
	"wireguard-tools: ".&$y($st->{'pkg_tools'}).", wireguard: ".&$y($st->{'pkg_wireguard'}));
$t .= &ui_table_row($text{'inst_kernel'}, &$y($st->{'kernel'}));
$t .= &ui_table_row($text{'inst_qr'}, &$y($st->{'qrencode'}));
$t .= &ui_table_row($text{'inst_ipt'}, &$y($st->{'iptables'}));
$t .= &ui_table_row($text{'inst_conf'}, &$y($st->{'conf'}));
$t .= &ui_table_row($text{'inst_run'}, &$y($st->{'up'}));
$t .= &ui_table_row($text{'inst_boot'}, &$y($st->{'enabled'}));
$t .= &ui_table_row($text{'inst_ufw'}, $text{'inst_ufw_'.$st->{'ufw'}});
$t .= &ui_table_end();
return $t;
}

# conf_port()
# ListenPort z wg0.conf bez volania wg (funguje aj po odinštalovaní balíkov)
sub conf_port
{
my ($head) = &parse_conf();
my ($p) = join("\n", @$head) =~ /^\s*ListenPort\s*=\s*(\d+)/m;
return $p;
}

# secure_delete(file)
# Prepíše súbor (shred) a zmaže ho. Nikdy nemaže adresáre.
sub secure_delete
{
my ($f) = @_;
return 0 if (!-e $f && !-l $f);
if (-f $f && !-l $f && &has_command("shred")) {
	&run_cmd("shred -u -- ".quotemeta($f));
	}
unlink($f) if (-e $f || -l $f);
return !-e $f && !-l $f;
}

# uninstall_wireguard(\%opts)
# Odinštalovanie s bezpečným upratovaním. Možnosti: backup, ufw, sysctl,
# remove_conf, remove_packages. Maže len súbory, ktoré vytvára modul a skripty
# (wg0.conf, zálohy, .endpoint, clients/), nikdy celý adresár naslepo.
# Vráti (\@steps, $ok).
sub uninstall_wireguard
{
my ($o) = @_;
my @s;
my $fail = sub { push(@s, [ 'err', $_[0] ]); return (\@s, 0); };
my $if = $config{'interface'};
my $svc = &service_name();
my $dir = $config{'conf_dir'};
my ($rc, $out, $err);

# Ochrana: adresár musí byť absolútna cesta s aspoň dvoma zložkami (/etc/wireguard)
return &$fail($text{'err_dir'})
	if ($dir !~ m{^/(?:[^/\0]+/)+[^/\0]+$} || $dir =~ m{(?:^|/)\.\.(?:/|$)});
return &$fail($text{'err_if'}) if ($if !~ /^[A-Za-z0-9_.-]+$/);
my $port = -r &conf_file() ? &conf_port() : undef;

# 1. Záloha (pred čímkoľvek, pri chybe sa nič nemaže)
if ($o->{'backup'} && -d $dir) {
	my $arch = $config{'backup_dir'}."/wireguard-backup-".
		   strftime("%Y%m%d-%H%M%S", localtime()).".tar.gz";
	($rc, $out, $err) = &run_cmd("umask 077 && tar -czf ".quotemeta($arch).
				     " -C ".quotemeta($dir)." .");
	return &$fail(&text('uninst_backup_err', &html_escape($err || $out))) if ($rc);
	push(@s, [ 'ok', &text('uninst_backup', "<tt>".&html_escape($arch)."</tt>") ]);
	}

# 2. Zastavenie a vypnutie služby (PostDown odstráni pravidlá iptables)
if (&has_command("systemctl")) {
	($rc, $out, $err) = &run_cmd("systemctl stop ".quotemeta($svc));
	push(@s, $rc ? [ 'warn', &text('uninst_stop_err', &html_escape($err || $out)) ]
		     : [ 'ok', $text{'uninst_stopped'} ]);
	($rc, $out, $err) = &run_cmd("systemctl disable ".quotemeta($svc));
	push(@s, $rc ? [ 'warn', &text('uninst_disable_err', &html_escape($err || $out)) ]
		     : [ 'ok', $text{'uninst_disabled'} ]);
	}
if (&has_command($config{'wg'}) && &interface_up()) {
	&run_cmd($config{'wg_quick'}." down ".quotemeta(&conf_file()));
	&run_cmd("ip link delete dev ".quotemeta($if)) if (&interface_up());
	}
if (&has_command($config{'wg'})) {
	push(@s, &interface_up() ? [ 'warn', &text('uninst_still_up', "<tt>$if</tt>") ]
				 : [ 'ok', &text('uninst_down', "<tt>$if</tt>") ]);
	}

# 3. Pravidlo v ufw
if ($o->{'ufw'} && $port && &ufw_state() eq 'active') {
	($rc, $out, $err) = &run_cmd("ufw --force delete allow ".quotemeta("$port/udp"));
	push(@s, $rc ? [ 'warn', &text('uninst_ufw_err', &html_escape($err || $out)) ]
		     : [ 'ok', &text('uninst_ufw', "<tt>$port/udp</tt>") ]);
	}

# 4. Súbor sysctl (bežiaci forwarding sa nemení, môžu ho potrebovať iné služby)
if ($o->{'sysctl'} && -e $config{'sysctl_file'}) {
	unlink($config{'sysctl_file'});
	push(@s, [ 'ok', &text('uninst_sysctl', "<tt>".&html_escape($config{'sysctl_file'})."</tt>") ]);
	}

# 5. Súbory v adresári konfigurácie
if ($o->{'remove_conf'} && -d $dir) {
	my @del;
	push(@del, &conf_file());
	if (opendir(my $dh, $dir)) {
		foreach my $f (readdir($dh)) {
			push(@del, "$dir/$f") if ($f =~ /^\Q$if\E\.conf\.bak\./);
			}
		closedir($dh);
		}
	push(@del, &endpoint_file());
	my $cl = "$dir/clients";
	if (-d $cl && opendir(my $dh, $cl)) {
		foreach my $f (readdir($dh)) {
			push(@del, "$cl/$f") if ($f ne "." && $f ne ".." && -f "$cl/$f");
			}
		closedir($dh);
		}
	my $n = 0;
	foreach my $f (@del) {
		$n++ if (&secure_delete($f));
		}
	rmdir($cl) if (-d $cl);
	push(@s, [ 'ok', &text('uninst_files', $n) ]);
	if (rmdir($dir)) {
		push(@s, [ 'ok', &text('uninst_dir_removed', "<tt>".&html_escape($dir)."</tt>") ]);
		}
	else {
		push(@s, [ 'warn', &text('uninst_dir_left', "<tt>".&html_escape($dir)."</tt>") ]);
		}
	}

# 6. Balíky
if ($o->{'remove_packages'}) {
	if (&has_command("apt-get")) {
		($rc, $out, $err) = &run_cmd("DEBIAN_FRONTEND=noninteractive apt-get ".
			"remove -y --purge wireguard wireguard-tools");
		push(@s, $rc ? [ 'err', &text('uninst_pkg_err', &html_escape($err || $out)) ]
			     : [ 'ok', $text{'uninst_pkgs'} ]);
		}
	else {
		push(@s, [ 'warn', $text{'setup_noapt'} ]);
		}
	}

my $ok = (grep { $_->[0] eq 'err' } @s) ? 0 : 1;
return (\@s, $ok);
}

# get_server_settings()
# Aktuálne nastavenia servera na úpravu: port, v4, v6, nic, pubkey
sub get_server_settings
{
return undef if (!-r &conf_file());
my ($head, $peers) = &parse_conf();
my $t = join("\n", @$head);
my %s;
($s{'port'}) = $t =~ /^\s*ListenPort\s*=\s*(\d+)/m;
my ($addr) = $t =~ /^\s*Address\s*=\s*(.+?)\s*$/m;
($s{'privkey'}) = $t =~ /^\s*PrivateKey\s*=\s*(\S+)/m;
return undef if (!$addr || !$s{'port'} || !$s{'privkey'});
my ($v4, $v6) = split(/\s*,\s*/, $addr);
$s{'v4'} = $v4;
$s{'v6'} = defined($v6) ? $v6 : "";
($s{'nic'}) = $t =~ /^\s*PostUp\s*=\s*iptables\s+-t\s+nat\s+-A\s+POSTROUTING\s+-o\s+(\S+)/m;
$s{'nic'} = "" if (!defined($s{'nic'}));
$s{'pubkey'} = &gen_key("printf %s ".quotemeta($s{'privkey'})." | ".
			$config{'wg'}." pubkey", "wg pubkey");
return \%s;
}

# apply_server_edit(\%new, regen_key)
# Zmení port, adresy v tuneli, kartu a voliteľne kľúč servera v [Interface],
# presunie klientov do novej podsiete a reštartuje bežiaci tunel.
# Vráti (\@steps, $ok, $affects_clients).
sub apply_server_edit
{
my ($n, $regen) = @_;
my @s;
my $fail = sub { push(@s, [ 'err', $_[0] ]); return (\@s, 0, 0); };
my $if = $config{'interface'};
my ($rc, $out, $err);

my $old = &get_server_settings();
return &$fail($text{'err_server'}) if (!$old);
my ($head, $peers) = &parse_conf();

my ($newnet) = $n->{'v4'} =~ /^(\d+\.\d+\.\d+)\./;
my ($newhost) = $n->{'v4'} =~ /\.(\d+)\//;
my ($oldnet) = $old->{'v4'} =~ /^(\d+\.\d+\.\d+)\./;
my $v6base = "";
$v6base = $1 if ($n->{'v6'} ne "" && $n->{'v6'} =~ /^(.+?)::/);
my $oldv6 = "";
$oldv6 = $1 if ($old->{'v6'} ne "" && $old->{'v6'} =~ /^(.+?)::/);

foreach my $p (@$peers) {
	return &$fail(&text('err_octet_clash', $newhost))
		if (defined($p->{'octet'}) && $p->{'octet'} == $newhost);
	}

my $newkey = $regen ? &gen_key($config{'wg'}." genkey", "wg genkey") : undef;
my ($op, $np, $on, $nn) = ($old->{'port'}, $n->{'port'}, $old->{'nic'}, $n->{'nic'});
my $addr = $n->{'v4'};
$addr .= ",".$n->{'v6'} if ($n->{'v6'} ne "");
my @newhead;
foreach my $b (@$head) {
	if ($b =~ /^[ \t]*\[Interface\]/m) {
		$b =~ s/^([ \t]*Address[ \t]*=[ \t]*).*$/$1$addr/m;
		$b =~ s/^([ \t]*ListenPort[ \t]*=[ \t]*)\d+/$1$np/m;
		$b =~ s/^([ \t]*PrivateKey[ \t]*=[ \t]*).*$/$1$newkey/m if (defined($newkey));
		$b =~ s/(--dport[ \t]+)\Q$op\E\b/$1$np/g if ($op ne $np);
		$b =~ s/(\s-[io][ \t]+)\Q$on\E(?=\s|$)/$1$nn/g if ($on ne "" && $on ne $nn);
		}
	push(@newhead, $b);
	}

# Klienti sa presunú do novej podsiete (rovnaké posledné číslo)
if ($newnet ne $oldnet || $v6base ne $oldv6) {
	foreach my $p (@$peers) {
		next if (!defined($p->{'octet'}));
		my $allowed = "$newnet.$p->{'octet'}/32";
		$allowed .= ",".$v6base."::".$p->{'octet'}."/128" if ($v6base ne "");
		$p->{'text'} =~ s/^([ \t]*AllowedIPs[ \t]*=[ \t]*).*$/$1$allowed/m;
		$p->{'allowed'} = $allowed;
		$p->{'ip'} = "$newnet.$p->{'octet'}";
		}
	}

&write_conf(\@newhead, $peers);
push(@s, [ 'ok', &text('edit_conf', "<tt>".&html_escape(&conf_file())."</tt>") ]);
push(@s, [ 'ok', $text{'edit_newkey'} ]) if ($regen);

# Zmena portu: ufw
if ($op ne $np && &ufw_state() eq 'active') {
	&run_cmd("ufw --force delete allow ".quotemeta("$op/udp"));
	($rc, $out, $err) = &run_cmd("ufw allow ".quotemeta("$np/udp")." comment WireGuard");
	push(@s, $rc ? [ 'warn', &text('setup_ufw_err', &html_escape($err || $out)) ]
		     : [ 'ok', &text('edit_ufw', "<tt>$op/udp</tt>", "<tt>$np/udp</tt>") ]);
	}

# Reštart bežiaceho tunela (zmena PostUp a adries vyžaduje reštart)
if (&interface_up()) {
	($rc, $out, $err) = &run_cmd("systemctl restart ".quotemeta(&service_name()));
	if ($rc) {
		push(@s, [ 'err', &text('setup_start_err', &html_escape($err || $out)) ]);
		}
	else {
		push(@s, [ 'ok', $text{'edit_restarted'} ]);
		}
	}
else {
	push(@s, [ 'ok', $text{'edit_not_running'} ]);
	}

my $affects = ($regen || $op ne $np || $n->{'v4'} ne $old->{'v4'} ||
	       $n->{'v6'} ne $old->{'v6'}) ? 1 : 0;
my $ok = (grep { $_->[0] eq 'err' } @s) ? 0 : 1;
return (\@s, $ok, $affects);
}

1;
