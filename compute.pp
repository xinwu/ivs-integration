
$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"

# assign ip to ivs internal port
# example ['storage,192.168.1.1/24', 'management,192.168.3.1/24']

define ivs_internal_port_ip {
    $port_ip = split($name, ',')
    file_line { "ip link set ${port_ip[0]} up":
        path  => '/etc/rc.local',
        line  => "ip link set ${port_ip[0]} up",
        match => "^ip link set ${port_ip[0]} up",
    }->
    file_line { "ifconfig ${port_ip[0]} ${port_ip[1]}":
        path  => '/etc/rc.local',
        line  => "ifconfig ${port_ip[0]} ${port_ip[1]}",
        match => "^ifconfig ${port_ip[0]} ${port_ip[1]}$",
    }
}

class ivs_internal_port_ips {
    $port_ips = [%(port_ips)s]
    file { "/etc/rc.local":
        ensure  => file,
        mode    => 0777,
    }->
    file_line { "remove exit 0":
        path    => '/etc/rc.local',
        ensure  => absent,
        line    => "exit 0",
    }->
    file_line { "restart ivs":
        path    => '/etc/rc.local',
        line    => "service ivs restart",
        match   => "^service ivs restart$",
    }->
    ivs_internal_port_ip { $port_ips:
    }->
    file_line { "add exit 0":
        path    => '/etc/rc.local',
        line    => "exit 0",
    }
}

include ivs_internal_port_ips

# ivs configruation and service
file { '/etc/default/ivs':
    ensure  => file,
    mode    => 0644,
    content => "%(ivs_daemon_args)s",
    notify  => Service['ivs'],
}
service { 'ivs':
    ensure     => 'running',
    provider   => 'upstart',
    hasrestart => 'true',
    hasstatus  => 'true',
    subscribe  => File['/etc/default/ivs'],
}

# config /etc/neutron/neutron.conf
ini_setting { "neutron.conf service_plugins":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'service_plugins',
  value             => 'bsn_l3',
}
ini_setting { "neutron.conf dhcp_agents_per_network":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'dhcp_agents_per_network',
  value             => '1',
}

# config neutron-bsn-agent conf
file { '/etc/init/neutron-bsn-agent.conf':
    ensure => present,
    content => "
description \"Neutron BSN Agent\"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
script
    exec /usr/local/bin/neutron-bsn-agent --config-file=/etc/neutron/neutron.conf --config-file=/etc/neutron/plugins/ml2/ml2_conf.ini --log-file=/var/log/neutron/neutron-bsn-agent.log
end script
",
}
file { '/etc/init.d/neutron-bsn-agent':
    ensure => link,
    target => '/lib/init/upstart-job',
    notify => Service['neutron-bsn-agent'],
}
service {'neutron-bsn-agent':
    ensure     => 'running',
    provider   => 'upstart',
    hasrestart => 'true',
    hasstatus  => 'true',
    subscribe  => File['/etc/init/neutron-bsn-agent.conf'],
}

# stop and disable neutron-plugin-openvswitch-agent
service { 'neutron-plugin-openvswitch-agent':
  ensure   => 'stopped',
  enable   => false,
  provider => 'upstart',
}

