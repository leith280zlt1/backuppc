#============================================================= -*-perl-*-
#
# BackupPC::Storage::Text package
#
# DESCRIPTION
#
#   This library defines a BackupPC::Storage::Text class that implements
#   BackupPC's persistent state storage (config, host info, backup
#   and restore info) using text files.
#
# AUTHOR
#   Craig Barratt  <cbarratt@users.sourceforge.net>
#
# COPYRIGHT
#   Copyright (C) 2004  Craig Barratt
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#========================================================================
#
# Version 2.1.0, released 20 Jun 2004.
#
# See http://backuppc.sourceforge.net.
#
#========================================================================

package BackupPC::Storage::Text;

use strict;
use vars qw(%Conf);
use Data::Dumper;
use File::Path;
use Fcntl qw/:flock/;

sub new
{
    my $class = shift;
    my($flds, $paths) = @_;

    my $s = bless {
	%$flds,
	%$paths,
    }, $class;
    return $s;
}

sub setPaths
{
    my $class = shift;
    my($paths) = @_;

    foreach my $v ( keys(%$paths) ) {
        $class->{$v} = $paths->{$v};
    }
}

sub BackupInfoRead
{
    my($s, $host) = @_;
    local(*BK_INFO, *LOCK);
    my(@Backups);

    flock(LOCK, LOCK_EX) if open(LOCK, "$s->{TopDir}/pc/$host/LOCK");
    if ( open(BK_INFO, "$s->{TopDir}/pc/$host/backups") ) {
	binmode(BK_INFO);
        while ( <BK_INFO> ) {
            s/[\n\r]+//;
            next if ( !/^(\d+\t(incr|full|partial).*)/ );
            $_ = $1;
            @{$Backups[@Backups]}{@{$s->{BackupFields}}} = split(/\t/);
        }
        close(BK_INFO);
    }
    close(LOCK);
    return @Backups;
}

sub BackupInfoWrite
{
    my($s, $host, @Backups) = @_;
    my($i, $contents, $fileOk);

    #
    # Generate the file contents
    #
    for ( $i = 0 ; $i < @Backups ; $i++ ) {
        my %b = %{$Backups[$i]};
        $contents .= join("\t", @b{@{$s->{BackupFields}}}) . "\n";
    }
    
    #
    # Write the file
    #
    return $s->TextFileWrite("$s->{TopDir}/pc/$host", "backups", $contents);
}

sub RestoreInfoRead
{
    my($s, $host) = @_;
    local(*RESTORE_INFO, *LOCK);
    my(@Restores);

    flock(LOCK, LOCK_EX) if open(LOCK, "$s->{TopDir}/pc/$host/LOCK");
    if ( open(RESTORE_INFO, "$s->{TopDir}/pc/$host/restores") ) {
	binmode(RESTORE_INFO);
        while ( <RESTORE_INFO> ) {
            s/[\n\r]+//;
            next if ( !/^(\d+.*)/ );
            $_ = $1;
            @{$Restores[@Restores]}{@{$s->{RestoreFields}}} = split(/\t/);
        }
        close(RESTORE_INFO);
    }
    close(LOCK);
    return @Restores;
}

sub RestoreInfoWrite
{
    my($s, $host, @Restores) = @_;
    local(*RESTORE_INFO, *LOCK);
    my($i, $contents, $fileOk);

    #
    # Generate the file contents
    #
    for ( $i = 0 ; $i < @Restores ; $i++ ) {
        my %b = %{$Restores[$i]};
        $contents .= join("\t", @b{@{$s->{RestoreFields}}}) . "\n";
    }

    #
    # Write the file
    #
    return $s->TextFileWrite("$s->{TopDir}/pc/$host", "restores", $contents);
}

sub ArchiveInfoRead
{
    my($s, $host) = @_;
    local(*ARCHIVE_INFO, *LOCK);
    my(@Archives);

    flock(LOCK, LOCK_EX) if open(LOCK, "$s->{TopDir}/pc/$host/LOCK");
    if ( open(ARCHIVE_INFO, "$s->{TopDir}/pc/$host/archives") ) {
        binmode(ARCHIVE_INFO);
        while ( <ARCHIVE_INFO> ) {
            s/[\n\r]+//;
            next if ( !/^(\d+.*)/ );
            $_ = $1;
            @{$Archives[@Archives]}{@{$s->{ArchiveFields}}} = split(/\t/);
        }
        close(ARCHIVE_INFO);
    }
    close(LOCK);
    return @Archives;
}

sub ArchiveInfoWrite
{
    my($s, $host, @Archives) = @_;
    local(*ARCHIVE_INFO, *LOCK);
    my($i, $contents, $fileOk);

    #
    # Generate the file contents
    #
    for ( $i = 0 ; $i < @Archives ; $i++ ) {
        my %b = %{$Archives[$i]};
        $contents .= join("\t", @b{@{$s->{ArchiveFields}}}) . "\n";
    }

    #
    # Write the file
    #
    return $s->TextFileWrite("$s->{TopDir}/pc/$host", "archives", $contents);
}

#
# Write a text file as safely as possible.  We write to
# a new file, verify the file, and the rename the file.
# The previous version of the file is renamed with a
# .old extension.
#
sub TextFileWrite
{
    my($s, $dir, $file, $contents) = @_;
    local(*FD, *LOCK);
    my($fileOk);

    mkpath($dir, 0, 0775) if ( !-d $dir );
    if ( open(FD, ">", "$dir/$file.new") ) {
	binmode(FD);
        print FD $contents;
        close(FD);
        #
        # verify the file
        #
        if ( open(FD, "<", "$dir/$file.new") ) {
            binmode(FD);
            if ( join("", <FD>) ne $contents ) {
                return "TextFileWrite: Failed to verify $dir/$file.new";
            } else {
                $fileOk = 1;
            }
            close(FD);
        }
    }
    if ( $fileOk ) {
        my $lock;
        
        if ( open(LOCK, "$dir/LOCK") || open(LOCK, ">", "$dir/LOCK") ) {
            $lock = 1;
            flock(LOCK, LOCK_EX);
        }
        if ( -s "$dir/$file" ) {
            unlink("$dir/$file.old")               if ( -f "$dir/$file.old" );
            rename("$dir/$file", "$dir/$file.old") if ( -f "$dir/$file" );
        } else {
            unlink("$dir/$file") if ( -f "$dir/$file" );
        }
        rename("$dir/$file.new", "$dir/$file") if ( -f "$dir/$file.new" );
        close(LOCK) if ( $lock );
    } else {
        return "TextFileWrite: Failed to write $dir/$file.new";
    }
    return;
}

sub ConfigDataRead
{
    my($s, $host) = @_;
    my($ret, $mesg, $config, @configs);

    #
    # TODO: add lock
    #
    my $conf = {};

    if ( defined($host) ) {
	push(@configs, "$s->{TopDir}/conf/$host.pl")
		if ( $host ne "config" && -f "$s->{TopDir}/conf/$host.pl" );
	push(@configs, "$s->{TopDir}/pc/$host/config.pl")
		if ( -f "$s->{TopDir}/pc/$host/config.pl" );
    } else {
	push(@configs, "$s->{TopDir}/conf/config.pl");
    }
    foreach $config ( @configs ) {
        %Conf = ();
        if ( !defined($ret = do $config) && ($! || $@) ) {
            $mesg = "Couldn't open $config: $!" if ( $! );
            $mesg = "Couldn't execute $config: $@" if ( $@ );
            $mesg =~ s/[\n\r]+//;
            return ($mesg, $conf);
        }
        %$conf = ( %$conf, %Conf );
    }
    #
    # Promote BackupFilesOnly and BackupFilesExclude to hashes
    #
    foreach my $param qw(BackupFilesOnly BackupFilesExclude) {
        next if ( !defined($conf->{$param}) || ref($conf->{$param}) eq "HASH" );
        $conf->{$param} = [ $conf->{$param} ]
                                if ( ref($conf->{$param}) ne "ARRAY" );
        $conf->{$param} = { "*" => $conf->{$param} };
    }

    return (undef, $conf);
}

sub ConfigDataWrite
{
    my($s, $host, $newConf) = @_;

    my($confDir) = $host eq "" ? "$s->{TopDir}/conf"
			       : "$s->{TopDir}/pc/$host";

    my($err, $contents) = $s->ConfigFileMerge("$confDir/config.pl", $newConf);
    if ( defined($err) ) {
        return $err;
    } else {
        #
        # Write the file
        #
        return $s->TextFileWrite($confDir, "config.pl", $contents);
    }
}

sub ConfigFileMerge
{
    my($s, $inFile, $newConf) = @_;
    local(*C);
    my($contents, $out);
    my $comment = 1;
    my $skipVar = 0;
    my $endLine = undef;
    my $done = {};

    if ( -f $inFile ) {
        #
        # Match existing settings in current config file
        #
        open(C, $inFile)
            || return ("ConfigFileMerge: can't open/read $inFile", undef);
        binmode(C);

        while ( <C> ) {
            if ( $comment && /^\s*#/ ) {
                $out .= $_;
            } elsif ( /^\s*\$Conf\{([^}]*)\}\s*=/ ) {
                my $var = $1;
                if ( exists($newConf->{$var}) ) { 
                    $contents .= $out;
                    my $d = Data::Dumper->new([$newConf->{$var}], [*value]);
                    $d->Indent(1);
                    $d->Terse(1);
                    my $value = $d->Dump;
                    $value =~ s/(.*)\n/$1;\n/s;
                    $contents .= "\$Conf{$var} = " . $value;
                    $done->{$var} = 1;
                }
                $endLine = $1 if ( /^\s*\$Conf\{[^}]*} *= *<<(.*);/ );
                $endLine = $1 if ( /^\s*\$Conf\{[^}]*} *= *<<'(.*)';/ );
                $out = "";
                $skipVar = 1;
            } elsif ( $skipVar ) {
                if ( !defined($endLine) && (/^\s*[\r\n]*$/ || /^\s*#/) ) {
                    $skipVar = 0;
                    $comment = 1;
                    $out .= $_;
                }
                if ( defined($endLine) && /^\Q$endLine\E[\n\r]*$/ ) {
                    $endLine = undef;
                    $skipVar = 0;
                    $comment = 1;
                }
            } else {
                $out .= $_;
            }
        }
        close(C);
        $contents .= $out;
    }

    #
    # Add new entries not matched in current config file
    #
    foreach my $var ( sort(keys(%$newConf)) ) {
	next if ( $done->{$var} );
	my $d = Data::Dumper->new([$newConf->{$var}], [*value]);
	$d->Indent(1);
	$d->Terse(1);
	my $value = $d->Dump;
	$value =~ s/(.*)\n/$1;\n/s;
	$contents .= "\$Conf{$var} = " . $value;
	$done->{$var} = 1;
    }
    return (undef, $contents);
}

#
# Return the mtime of the config file
#
sub ConfigMTime
{
    my($s) = @_;
    return (stat("$s->{TopDir}/conf/config.pl"))[9];
}

#
# Returns information from the host file in $s->{TopDir}/conf/hosts.
# With no argument a ref to a hash of hosts is returned.  Each
# hash contains fields as specified in the hosts file.  With an
# argument a ref to a single hash is returned with information
# for just that host.
#
sub HostInfoRead
{
    my($s, $host) = @_;
    my(%hosts, @hdr, @fld);
    local(*HOST_INFO, *LOCK);

    flock(LOCK, LOCK_EX) if open(LOCK, "$s->{TopDir}/pc/$host/LOCK");
    if ( !open(HOST_INFO, "$s->{TopDir}/conf/hosts") ) {
        print(STDERR "Can't open $s->{TopDir}/conf/hosts\n");
        close(LOCK);
        return {};
    }
    binmode(HOST_INFO);
    while ( <HOST_INFO> ) {
        s/[\n\r]+//;
        s/#.*//;
        s/\s+$//;
        next if ( /^\s*$/ || !/^([\w\.\\-]+\s+.*)/ );
        #
        # Split on white space, except if preceded by \
        # using zero-width negative look-behind assertion
	# (always wanted to use one of those).
        #
        @fld = split(/(?<!\\)\s+/, $1);
        #
        # Remove any \
        #
        foreach ( @fld ) {
            s{\\(\s)}{$1}g;
        }
        if ( @hdr ) {
            if ( defined($host) ) {
                next if ( lc($fld[0]) ne lc($host) );
                @{$hosts{$fld[0]}}{@hdr} = @fld;
		close(HOST_INFO);
                close(LOCK);
                return \%hosts;
            } else {
                @{$hosts{$fld[0]}}{@hdr} = @fld;
            }
        } else {
            @hdr = @fld;
        }
    }
    close(HOST_INFO);
    close(LOCK);
    return \%hosts;
}

#
# Writes new hosts information to the hosts file in $s->{TopDir}/conf/hosts.
# With no argument a ref to a hash of hosts is returned.  Each
# hash contains fields as specified in the hosts file.  With an
# argument a ref to a single hash is returned with information
# for just that host.
#
sub HostInfoWrite
{
    my($s, $hosts) = @_;
    my($gotHdr, @fld, $hostText, $contents);
    local(*HOST_INFO);

    if ( !open(HOST_INFO, "$s->{TopDir}/conf/hosts") ) {
        return "Can't open $s->{TopDir}/conf/hosts";
    }
    foreach my $host ( keys(%$hosts) ) {
        my $name = "$hosts->{$host}{host}";
        my $rest = "\t$hosts->{$host}{dhcp}"
                 . "\t$hosts->{$host}{user}"
                 . "\t$hosts->{$host}{moreUsers}";
        $name =~ s/ /\\ /g;
        $rest =~ s/ //g;
        $hostText->{$host} = $name . $rest;
    }
    binmode(HOST_INFO);
    while ( <HOST_INFO> ) {
        s/[\n\r]+//;
        if ( /^\s*$/ || /^\s*#/ ) {
            $contents .= $_ . "\n";
            next;
        }
        if ( !$gotHdr ) {
            $contents .= $_ . "\n";
            $gotHdr = 1;
            next;
        }
        @fld = split(/(?<!\\)\s+/, $1);
        #
        # Remove any \
        #
        foreach ( @fld ) {
            s{\\(\s)}{$1}g;
        }
        if ( defined($hostText->{$fld[0]}) ) {
            $contents .= $hostText->{$fld[0]} . "\n";
            delete($hostText->{$fld[0]});
        }
    }
    foreach my $host ( sort(keys(%$hostText)) ) {
        $contents .= $hostText->{$host} . "\n";
        delete($hostText->{$host});
    }
    close(HOST_INFO);

    #
    # Write and verify the new host file
    #
    return $s->TextFileWrite("$s->{TopDir}/conf", "hosts", $contents);
}

#
# Return the mtime of the hosts file
#
sub HostsMTime
{
    my($s) = @_;
    return (stat("$s->{TopDir}/conf/hosts"))[9];
}

1;