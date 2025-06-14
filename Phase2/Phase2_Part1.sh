#!/bin/bash
# =============================================================================
# Phase 2: MikroTik Integration - Part 1: Core Setup and Device Management
# Version: 2.0
# Description: Complete implementation of MikroTik device management
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Directories
SYSTEM_DIR="/opt/mikrotik-vpn"
APP_DIR="$SYSTEM_DIR/app"
CONFIG_DIR="$SYSTEM_DIR/configs"
LOG_DIR="/var/log/mikrotik-vpn"
SCRIPT_DIR="$SYSTEM_DIR/scripts"

# Create log directory if not exists
mkdir -p "$LOG_DIR"

# Load environment - IMPORTANT: This loads all passwords from Phase 1
if [[ -f "$CONFIG_DIR/setup.env" ]]; then
    source "$CONFIG_DIR/setup.env"
else
    echo -e "${RED}ERROR: Configuration file not found. Please run Phase 1 first.${NC}"
    exit 1
fi

# Verify required passwords are loaded
if [[ -z "${MONGO_APP_PASSWORD:-}" ]] || [[ -z "${REDIS_PASSWORD:-}" ]]; then
    echo -e "${RED}ERROR: Required passwords not found in configuration.${NC}"
    echo "Please ensure Phase 1 was completed successfully."
    exit 1
fi

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_DIR/phase2.log"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_DIR/phase2.log"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_DIR/phase2.log"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_DIR/phase2.log"
}

# =============================================================================
# PHASE 2.1: MIKROTIK DEVICE MANAGEMENT
# =============================================================================

phase2_1_device_management() {
    log "=== Phase 2.1: Setting up MikroTik Device Management ==="
    
    # Create device management directories
    mkdir -p "$APP_DIR/src/mikrotik"
    mkdir -p "$APP_DIR/src/mikrotik/lib"
    mkdir -p "$APP_DIR/src/mikrotik/templates"
    mkdir -p "$APP_DIR/src/mikrotik/scripts"
    mkdir -p "$APP_DIR/controllers"
    mkdir -p "$APP_DIR/routes"
    mkdir -p "$APP_DIR/models"
    
    # Install MikroTik specific dependencies
    cd "$APP_DIR"
    log "Installing MikroTik dependencies..."
    npm install --save \
        node-routeros \
        mikrotik \
        ssh2 \
        node-schedule \
        ip \
        netmask \
        ping \
        snmp-native \
        @slack/webhook \
        @sendgrid/mail \
        pdfkit \
        exceljs \
        qrcode \
        handlebars \
        puppeteer \
        node-thermal-printer \
        nodemailer || {
        log_error "Failed to install npm dependencies"
        return 1
    }
    
    # Create Device model
    create_device_model
    
    # Create Organization model if not exists
    create_organization_model
    
    # Create MikroTik API wrapper
    create_mikrotik_api_wrapper
    
    # Create device discovery service
    create_device_discovery_service
    
    # Create device management controller
    create_device_management_controller
    
    # Create device monitoring service
    create_device_monitoring_service
    
    # Create MikroTik script templates
    create_mikrotik_templates
    
    log "Phase 2.1 completed!"
}

# Create Device model
create_device_model() {
    cat << 'EOF' > "$APP_DIR/models/Device.js"
const mongoose = require('mongoose');

const deviceSchema = new mongoose.Schema({
    organization: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Organization',
        required: true,
        index: true
    },
    name: {
        type: String,
        required: true,
        trim: true
    },
    serialNumber: {
        type: String,
        required: true,
        unique: true,
        trim: true,
        uppercase: true
    },
    macAddress: {
        type: String,
        required: true,
        unique: true,
        uppercase: true,
        trim: true,
        match: /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/
    },
    model: {
        type: String,
        trim: true
    },
    firmwareVersion: {
        type: String,
        trim: true
    },
    boardName: {
        type: String,
        trim: true
    },
    architecture: {
        type: String,
        trim: true
    },
    location: {
        name: String,
        address: String,
        coordinates: {
            lat: Number,
            lng: Number
        },
        timezone: {
            type: String,
            default: 'Asia/Bangkok'
        }
    },
    vpnIpAddress: {
        type: String,
        required: true,
        unique: true,
        match: /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/
    },
    vpnStatus: {
        connected: {
            type: Boolean,
            default: false
        },
        connectedAt: Date,
        disconnectedAt: Date,
        bytesIn: {
            type: Number,
            default: 0
        },
        bytesOut: {
            type: Number,
            default: 0
        }
    },
    configuration: {
        apiUsername: {
            type: String,
            required: true
        },
        apiPassword: {
            type: String,
            required: true
        },
        apiPort: {
            type: Number,
            default: 8728
        },
        apiSSL: {
            type: Boolean,
            default: false
        },
        sshPort: {
            type: Number,
            default: 22
        },
        winboxPort: {
            type: Number,
            default: 8291
        },
        webPort: {
            type: Number,
            default: 80
        },
        httpsPort: {
            type: Number,
            default: 443
        },
        lastTemplate: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'ConfigTemplate'
        },
        lastTemplateApplied: Date
    },
    features: {
        hotspot: {
            type: Boolean,
            default: true
        },
        vpn: {
            type: Boolean,
            default: true
        },
        firewall: {
            type: Boolean,
            default: true
        },
        qos: {
            type: Boolean,
            default: true
        },
        wireless: {
            type: Boolean,
            default: false
        },
        routing: {
            type: Boolean,
            default: false
        }
    },
    status: {
        type: String,
        enum: ['online', 'offline', 'maintenance', 'error', 'unknown'],
        default: 'unknown',
        index: true
    },
    health: {
        cpuUsage: Number,
        memoryUsage: Number,
        diskUsage: Number,
        temperature: Number,
        voltage: Number,
        uptime: String
    },
    lastSeen: Date,
    discoveredAt: Date,
    registeredAt: {
        type: Date,
        default: Date.now
    },
    alerts: [{
        type: {
            type: String,
            enum: ['info', 'warning', 'error', 'critical']
        },
        message: String,
        timestamp: {
            type: Date,
            default: Date.now
        },
        resolved: {
            type: Boolean,
            default: false
        },
        resolvedAt: Date,
        acknowledgedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        }
    }],
    backups: [{
        filename: String,
        size: Number,
        createdAt: {
            type: Date,
            default: Date.now
        },
        createdBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        configuration: String
    }],
    maintenanceWindows: [{
        description: String,
        startTime: Date,
        endTime: Date,
        recurring: {
            type: String,
            enum: ['once', 'daily', 'weekly', 'monthly']
        },
        createdBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        }
    }],
    notes: String,
    tags: [String],
    customFields: mongoose.Schema.Types.Mixed,
    isActive: {
        type: Boolean,
        default: true
    }
}, {
    timestamps: true
});

// Indexes
deviceSchema.index({ organization: 1, name: 1 });
deviceSchema.index({ organization: 1, status: 1 });
deviceSchema.index({ vpnIpAddress: 1 });
deviceSchema.index({ 'location.coordinates': '2dsphere' });

// Virtual for display name
deviceSchema.virtual('displayName').get(function() {
    return this.name + (this.location?.name ? ` (${this.location.name})` : '');
});

// Methods
deviceSchema.methods.updateHealth = function(metrics) {
    this.health = {
        cpuUsage: metrics.cpuLoad,
        memoryUsage: metrics.memoryUsage,
        diskUsage: metrics.diskUsage,
        temperature: metrics.temperature,
        voltage: metrics.voltage,
        uptime: metrics.uptime
    };
    this.lastSeen = new Date();
    return this.save();
};

deviceSchema.methods.addAlert = function(type, message) {
    this.alerts.push({
        type,
        message,
        timestamp: new Date()
    });
    
    // Keep only last 100 alerts
    if (this.alerts.length > 100) {
        this.alerts = this.alerts.slice(-100);
    }
    
    return this.save();
};

deviceSchema.methods.resolveAlert = function(alertId, userId) {
    const alert = this.alerts.id(alertId);
    if (alert) {
        alert.resolved = true;
        alert.resolvedAt = new Date();
        alert.acknowledgedBy = userId;
        return this.save();
    }
    return Promise.resolve(this);
};

// Statics
deviceSchema.statics.findByOrganization = function(organizationId) {
    return this.find({ 
        organization: organizationId,
        isActive: true 
    }).sort({ name: 1 });
};

deviceSchema.statics.updateStatuses = async function() {
    const devices = await this.find({ isActive: true });
    const now = new Date();
    const offlineThreshold = 5 * 60 * 1000; // 5 minutes
    
    for (const device of devices) {
        if (device.lastSeen && (now - device.lastSeen) > offlineThreshold) {
            if (device.status !== 'offline') {
                device.status = 'offline';
                await device.save();
            }
        }
    }
};

// Middleware
deviceSchema.pre('save', function(next) {
    // Ensure MAC address is uppercase
    if (this.macAddress) {
        this.macAddress = this.macAddress.toUpperCase();
    }
    
    // Ensure serial number is uppercase
    if (this.serialNumber) {
        this.serialNumber = this.serialNumber.toUpperCase();
    }
    
    next();
});

module.exports = mongoose.model('Device', deviceSchema);
EOF
}

# Create Organization model
create_organization_model() {
    cat << 'EOF' > "$APP_DIR/models/Organization.js"
const mongoose = require('mongoose');

const organizationSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true,
        trim: true
    },
    code: {
        type: String,
        unique: true,
        uppercase: true,
        trim: true
    },
    email: {
        type: String,
        required: true,
        lowercase: true,
        trim: true
    },
    phone: String,
    address: {
        street: String,
        city: String,
        state: String,
        country: String,
        postalCode: String
    },
    timezone: {
        type: String,
        default: 'Asia/Bangkok'
    },
    currency: {
        type: String,
        default: 'THB'
    },
    logo: String,
    website: String,
    settings: {
        deviceLimit: {
            type: Number,
            default: 100
        },
        userLimit: {
            type: Number,
            default: 10000
        },
        features: {
            hotspot: {
                type: Boolean,
                default: true
            },
            vouchers: {
                type: Boolean,
                default: true
            },
            payments: {
                type: Boolean,
                default: false
            },
            whiteLabel: {
                type: Boolean,
                default: false
            }
        },
        branding: {
            primaryColor: {
                type: String,
                default: '#2196F3'
            },
            secondaryColor: {
                type: String,
                default: '#FFC107'
            }
        }
    },
    subscription: {
        plan: {
            type: String,
            enum: ['trial', 'basic', 'pro', 'enterprise'],
            default: 'trial'
        },
        status: {
            type: String,
            enum: ['active', 'suspended', 'cancelled'],
            default: 'active'
        },
        startDate: Date,
        endDate: Date,
        autoRenew: {
            type: Boolean,
            default: true
        }
    },
    billing: {
        contactName: String,
        contactEmail: String,
        taxId: String,
        paymentMethod: String
    },
    createdBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    },
    isActive: {
        type: Boolean,
        default: true
    }
}, {
    timestamps: true
});

// Generate organization code
organizationSchema.pre('save', function(next) {
    if (!this.code) {
        this.code = this.name
            .substring(0, 3)
            .toUpperCase() + 
            Math.random().toString(36).substring(2, 5).toUpperCase();
    }
    next();
});

module.exports = mongoose.model('Organization', organizationSchema);
EOF
}

# Create MikroTik API wrapper
create_mikrotik_api_wrapper() {
    cat << 'EOF' > "$APP_DIR/src/mikrotik/lib/mikrotik-api.js"
const { RouterOSAPI } = require('node-routeros');
const EventEmitter = require('events');
const logger = require('../../../utils/logger');

class MikroTikAPI extends EventEmitter {
    constructor(config) {
        super();
        this.config = {
            host: config.host || config.vpnIpAddress,
            user: config.user || 'admin',
            password: config.password,
            port: config.port || 8728,
            timeout: config.timeout || 10000,
            tls: config.tls || false
        };
        this.connection = null;
        this.isConnected = false;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectDelay = 5000;
    }

    async connect() {
        try {
            this.connection = new RouterOSAPI(this.config);
            await this.connection.connect();
            this.isConnected = true;
            this.reconnectAttempts = 0;
            this.emit('connected');
            logger.info(`Connected to MikroTik device at ${this.config.host}`);
            return true;
        } catch (error) {
            logger.error(`Failed to connect to MikroTik device: ${error.message}`);
            this.emit('error', error);
            throw error;
        }
    }

    async disconnect() {
        if (this.connection) {
            await this.connection.close();
            this.isConnected = false;
            this.emit('disconnected');
            logger.info(`Disconnected from MikroTik device at ${this.config.host}`);
        }
    }

    async reconnect() {
        if (this.reconnectAttempts >= this.maxReconnectAttempts) {
            logger.error('Max reconnection attempts reached');
            this.emit('reconnectFailed');
            return false;
        }

        this.reconnectAttempts++;
        logger.info(`Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts})...`);
        
        await new Promise(resolve => setTimeout(resolve, this.reconnectDelay));
        
        try {
            await this.connect();
            return true;
        } catch (error) {
            return this.reconnect();
        }
    }

    async execute(command, params = {}) {
        if (!this.isConnected) {
            throw new Error('Not connected to MikroTik device');
        }

        try {
            const result = await this.connection.write(command, params);
            return result;
        } catch (error) {
            logger.error(`Command execution failed: ${error.message}`);
            
            if (error.message.includes('Connection') || error.message.includes('timeout')) {
                this.isConnected = false;
                this.emit('connectionLost');
                
                // Try to reconnect
                const reconnected = await this.reconnect();
                if (reconnected) {
                    // Retry the command
                    return this.execute(command, params);
                }
            }
            
            throw error;
        }
    }

    // System Information
    async getSystemInfo() {
        const [identity, resource, routerboard, health] = await Promise.all([
            this.execute('/system/identity/print'),
            this.execute('/system/resource/print'),
            this.execute('/system/routerboard/print').catch(() => null),
            this.execute('/system/health/print').catch(() => null)
        ]);

        return {
            identity: identity[0].name,
            version: resource[0].version,
            buildTime: resource[0]['build-time'],
            factorySoftware: resource[0]['factory-software'],
            freeMemory: resource[0]['free-memory'],
            totalMemory: resource[0]['total-memory'],
            freeHddSpace: resource[0]['free-hdd-space'],
            totalHddSpace: resource[0]['total-hdd-space'],
            cpuCount: resource[0]['cpu-count'],
            cpuFrequency: resource[0]['cpu-frequency'],
            cpuLoad: resource[0]['cpu-load'],
            uptime: resource[0].uptime,
            platform: resource[0].platform,
            boardName: resource[0]['board-name'],
            architecture: resource[0]['architecture-name'],
            routerboard: routerboard ? routerboard[0] : null,
            health: health || []
        };
    }

    // Interface Management
    async getInterfaces() {
        const interfaces = await this.execute('/interface/print');
        const stats = await this.execute('/interface/ethernet/print', { stats: true });
        
        return interfaces.map(iface => {
            const stat = stats.find(s => s.name === iface.name) || {};
            return {
                ...iface,
                stats: {
                    rxBytes: stat['rx-bytes'] || 0,
                    txBytes: stat['tx-bytes'] || 0,
                    rxPackets: stat['rx-packets'] || 0,
                    txPackets: stat['tx-packets'] || 0,
                    rxErrors: stat['rx-errors'] || 0,
                    txErrors: stat['tx-errors'] || 0
                }
            };
        });
    }

    // IP Address Management
    async getIPAddresses() {
        return this.execute('/ip/address/print');
    }

    async addIPAddress(address, interfaceName) {
        return this.execute('/ip/address/add', {
            address: address,
            interface: interfaceName
        });
    }

    // Hotspot Management
    async getHotspotServers() {
        return this.execute('/ip/hotspot/print');
    }

    async getHotspotProfiles() {
        return this.execute('/ip/hotspot/profile/print');
    }

    async getHotspotUsers() {
        return this.execute('/ip/hotspot/user/print');
    }

    async addHotspotUser(userData) {
        return this.execute('/ip/hotspot/user/add', {
            name: userData.username,
            password: userData.password,
            profile: userData.profile || 'default',
            'limit-uptime': userData.limitUptime,
            'limit-bytes-total': userData.limitBytesTotal,
            'mac-address': userData.macAddress,
            comment: userData.comment
        });
    }

    async removeHotspotUser(username) {
        const users = await this.getHotspotUsers();
        const user = users.find(u => u.name === username);
        
        if (user) {
            return this.execute('/ip/hotspot/user/remove', { '.id': user['.id'] });
        }
        
        throw new Error('User not found');
    }

    async updateHotspotUser(username, updates) {
        const users = await this.getHotspotUsers();
        const user = users.find(u => u.name === username);
        
        if (user) {
            return this.execute('/ip/hotspot/user/set', {
                '.id': user['.id'],
                ...updates
            });
        }
        
        throw new Error('User not found');
    }

    // Active Sessions
    async getHotspotActive() {
        return this.execute('/ip/hotspot/active/print');
    }

    async disconnectHotspotUser(sessionId) {
        return this.execute('/ip/hotspot/active/remove', { '.id': sessionId });
    }

    // Firewall Management
    async getFirewallRules() {
        const [filter, nat, mangle] = await Promise.all([
            this.execute('/ip/firewall/filter/print'),
            this.execute('/ip/firewall/nat/print'),
            this.execute('/ip/firewall/mangle/print')
        ]);

        return { filter, nat, mangle };
    }

    async addFirewallRule(chain, rule) {
        return this.execute(`/ip/firewall/${chain}/add`, rule);
    }

    // VPN Configuration
    async getVPNServers() {
        const [pptp, l2tp, sstp, ovpn] = await Promise.all([
            this.execute('/interface/pptp-server/print').catch(() => []),
            this.execute('/interface/l2tp-server/print').catch(() => []),
            this.execute('/interface/sstp-server/print').catch(() => []),
            this.execute('/interface/ovpn-server/print').catch(() => [])
        ]);

        return { pptp, l2tp, sstp, ovpn };
    }

    async getPPPSecrets() {
        return this.execute('/ppp/secret/print');
    }

    async addPPPSecret(secret) {
        return this.execute('/ppp/secret/add', {
            name: secret.name,
            password: secret.password,
            service: secret.service || 'any',
            profile: secret.profile || 'default',
            'local-address': secret.localAddress,
            'remote-address': secret.remoteAddress,
            comment: secret.comment
        });
    }

    // DHCP Management
    async getDHCPServers() {
        return this.execute('/ip/dhcp-server/print');
    }

    async getDHCPLeases() {
        return this.execute('/ip/dhcp-server/lease/print');
    }

    async addStaticDHCPLease(lease) {
        return this.execute('/ip/dhcp-server/lease/add', {
            address: lease.address,
            'mac-address': lease.macAddress,
            server: lease.server,
            comment: lease.comment
        });
    }

    // Queue Management (Bandwidth Control)
    async getQueues() {
        const [simple, tree] = await Promise.all([
            this.execute('/queue/simple/print'),
            this.execute('/queue/tree/print')
        ]);

        return { simple, tree };
    }

    async addSimpleQueue(queue) {
        return this.execute('/queue/simple/add', {
            name: queue.name,
            target: queue.target,
            'max-limit': queue.maxLimit,
            'burst-limit': queue.burstLimit,
            'burst-threshold': queue.burstThreshold,
            'burst-time': queue.burstTime,
            comment: queue.comment
        });
    }

    // DNS Management
    async getDNSSettings() {
        return this.execute('/ip/dns/print');
    }

    async getDNSStaticEntries() {
        return this.execute('/ip/dns/static/print');
    }

    async addDNSStaticEntry(entry) {
        return this.execute('/ip/dns/static/add', {
            name: entry.name,
            address: entry.address,
            ttl: entry.ttl || '1d',
            comment: entry.comment
        });
    }

    // Logging and Monitoring
    async getSystemLogs(limit = 100) {
        return this.execute('/log/print', {
            limit: limit.toString()
        });
    }

    async getTrafficStats(interfaceName) {
        const stats = await this.execute('/interface/monitor-traffic', {
            interface: interfaceName,
            once: true
        });

        return stats[0];
    }

    // Backup and Configuration
    async createBackup(filename) {
        await this.execute('/system/backup/save', {
            name: filename,
            'dont-encrypt': 'yes'
        });

        // Wait for backup to complete
        await new Promise(resolve => setTimeout(resolve, 2000));

        return filename;
    }

    async exportConfiguration() {
        const config = await this.execute('/export');
        return config.join('\n');
    }

    // Script Execution
    async runScript(script) {
        // Create temporary script
        const scriptName = `temp-script-${Date.now()}`;
        await this.execute('/system/script/add', {
            name: scriptName,
            source: script
        });

        try {
            // Run the script
            const result = await this.execute('/system/script/run', {
                number: scriptName
            });

            return result;
        } finally {
            // Clean up
            await this.execute('/system/script/remove', {
                numbers: scriptName
            }).catch(() => {});
        }
    }

    // Scheduled Tasks
    async getScheduledTasks() {
        return this.execute('/system/scheduler/print');
    }

    async addScheduledTask(task) {
        return this.execute('/system/scheduler/add', {
            name: task.name,
            'start-time': task.startTime || 'startup',
            interval: task.interval,
            'on-event': task.onEvent,
            comment: task.comment
        });
    }

    // Reboot and Shutdown
    async reboot() {
        return this.execute('/system/reboot');
    }

    async shutdown() {
        return this.execute('/system/shutdown');
    }
}

module.exports = MikroTikAPI;
EOF
}

# Create device discovery service
create_device_discovery_service() {
    cat << 'EOF' > "$APP_DIR/src/mikrotik/lib/device-discovery.js"
const dgram = require('dgram');
const { EventEmitter } = require('events');
const logger = require('../../../utils/logger');

class DeviceDiscovery extends EventEmitter {
    constructor(options = {}) {
        super();
        this.port = options.port || 5678;
        this.broadcastAddress = options.broadcastAddress || '255.255.255.255';
        this.timeout = options.timeout || 5000;
        this.socket = null;
        this.discovered = new Map();
    }

    async discover() {
        return new Promise((resolve, reject) => {
            this.socket = dgram.createSocket('udp4');
            const devices = [];
            const startTime = Date.now();

            this.socket.on('message', (msg, rinfo) => {
                try {
                    const device = this.parseDiscoveryMessage(msg, rinfo);
                    if (device && !this.discovered.has(device.macAddress)) {
                        this.discovered.set(device.macAddress, device);
                        devices.push(device);
                        this.emit('deviceFound', device);
                        logger.info(`Discovered MikroTik device: ${device.identity} at ${device.ipAddress}`);
                    }
                } catch (error) {
                    logger.error(`Failed to parse discovery message: ${error.message}`);
                }
            });

            this.socket.on('error', (error) => {
                logger.error(`Discovery error: ${error.message}`);
                this.socket.close();
                reject(error);
            });

            this.socket.bind(() => {
                this.socket.setBroadcast(true);
                
                // Send discovery packet
                const discoveryPacket = this.createDiscoveryPacket();
                this.socket.send(discoveryPacket, this.port, this.broadcastAddress, (error) => {
                    if (error) {
                        logger.error(`Failed to send discovery packet: ${error.message}`);
                    }
                });

                // Set timeout
                setTimeout(() => {
                    this.socket.close();
                    resolve(devices);
                }, this.timeout);
            });
        });
    }

    createDiscoveryPacket() {
        // MikroTik discovery protocol packet
        const packet = Buffer.alloc(4);
        packet.writeUInt32BE(0x00000000, 0);
        return packet;
    }

    parseDiscoveryMessage(msg, rinfo) {
        if (msg.length < 20) return null;

        try {
            // Parse MikroTik discovery response
            const device = {
                ipAddress: rinfo.address,
                port: rinfo.port,
                discoveredAt: new Date()
            };

            let offset = 0;
            while (offset < msg.length) {
                const type = msg.readUInt16BE(offset);
                const length = msg.readUInt16BE(offset + 2);
                const value = msg.slice(offset + 4, offset + 4 + length);

                switch (type) {
                    case 0x0001: // MAC address
                        device.macAddress = value.toString('hex').match(/.{2}/g).join(':');
                        break;
                    case 0x0005: // Identity
                        device.identity = value.toString('utf8');
                        break;
                    case 0x0007: // Platform
                        device.platform = value.toString('utf8');
                        break;
                    case 0x0008: // Version
                        device.version = value.toString('utf8');
                        break;
                    case 0x000A: // Uptime
                        device.uptime = value.readUInt32BE(0);
                        break;
                    case 0x000B: // Software ID
                        device.softwareId = value.toString('utf8');
                        break;
                    case 0x000C: // Board name
                        device.boardName = value.toString('utf8');
                        break;
                    case 0x0010: // Unpack
                        device.unpack = value.toString('utf8');
                        break;
                    case 0x0011: // IPv6
                        device.ipv6Address = this.parseIPv6(value);
                        break;
                    case 0x0014: // Interface name
                        device.interfaceName = value.toString('utf8');
                        break;
                    case 0x0015: // IPv4
                        device.ipv4Address = value.join('.');
                        break;
                }

                offset += 4 + length;
            }

            return device;
        } catch (error) {
            logger.error(`Failed to parse discovery data: ${error.message}`);
            return null;
        }
    }

    parseIPv6(buffer) {
        const parts = [];
        for (let i = 0; i < buffer.length; i += 2) {
            parts.push(buffer.readUInt16BE(i).toString(16));
        }
        return parts.join(':');
    }

    async scanNetwork(network) {
        const net = require('netmask').Netmask;
        const block = new net(network);
        const devices = [];

        logger.info(`Scanning network ${network} for MikroTik devices...`);

        // Scan each IP in the network
        block.forEach(async (ip) => {
            try {
                const device = await this.probeDevice(ip);
                if (device) {
                    devices.push(device);
                    this.emit('deviceFound', device);
                }
            } catch (error) {
                // Device not responding or not a MikroTik device
            }
        });

        return devices;
    }

    async probeDevice(ipAddress) {
        // Try to connect to MikroTik API port
        const net = require('net');
        
        return new Promise((resolve, reject) => {
            const socket = new net.Socket();
            socket.setTimeout(2000);

            socket.on('connect', () => {
                socket.destroy();
                resolve({
                    ipAddress,
                    port: 8728,
                    discoveredAt: new Date(),
                    probeMethod: 'api'
                });
            });

            socket.on('timeout', () => {
                socket.destroy();
                reject(new Error('Connection timeout'));
            });

            socket.on('error', (error) => {
                reject(error);
            });

            socket.connect(8728, ipAddress);
        });
    }
}

module.exports = DeviceDiscovery;
EOF
}

# Create device management controller
create_device_management_controller() {
    cat << 'EOF' > "$APP_DIR/controllers/deviceController.js"
const Device = require('../models/Device');
const MikroTikAPI = require('../src/mikrotik/lib/mikrotik-api');
const DeviceDiscovery = require('../src/mikrotik/lib/device-discovery');
const logger = require('../utils/logger');
const { validationResult } = require('express-validator');

class DeviceController {
    constructor() {
        this.connections = new Map();
        this.discovery = new DeviceDiscovery();
    }

    // Get all devices for organization
    async getDevices(req, res, next) {
        try {
            const devices = await Device.find({ 
                organization: req.user.organization 
            })
            .populate('organization')
            .sort({ name: 1 });

            // Check online status for each device
            const devicesWithStatus = await Promise.all(
                devices.map(async (device) => {
                    const isOnline = await this.checkDeviceStatus(device.vpnIpAddress);
                    return {
                        ...device.toObject(),
                        status: isOnline ? 'online' : 'offline'
                    };
                })
            );

            res.json({
                success: true,
                count: devicesWithStatus.length,
                data: devicesWithStatus
            });
        } catch (error) {
            next(error);
        }
    }

    // Get single device
    async getDevice(req, res, next) {
        try {
            const device = await Device.findOne({
                _id: req.params.id,
                organization: req.user.organization
            }).populate('organization');

            if (!device) {
                return res.status(404).json({
                    success: false,
                    error: 'Device not found'
                });
            }

            // Get real-time info if device is online
            let realtimeInfo = null;
            if (await this.checkDeviceStatus(device.vpnIpAddress)) {
                try {
                    const api = await this.getDeviceConnection(device);
                    realtimeInfo = await api.getSystemInfo();
                } catch (error) {
                    logger.error(`Failed to get real-time info: ${error.message}`);
                }
            }

            res.json({
                success: true,
                data: {
                    ...device.toObject(),
                    realtimeInfo
                }
            });
        } catch (error) {
            next(error);
        }
    }

    // Register new device
    async registerDevice(req, res, next) {
        try {
            const errors = validationResult(req);
            if (!errors.isEmpty()) {
                return res.status(400).json({
                    success: false,
                    errors: errors.array()
                });
            }

            const {
                name,
                serialNumber,
                macAddress,
                model,
                location,
                vpnIpAddress,
                apiUsername,
                apiPassword
            } = req.body;

            // Check if device already exists
            const existingDevice = await Device.findOne({
                $or: [
                    { serialNumber },
                    { macAddress: macAddress.toUpperCase() }
                ]
            });

            if (existingDevice) {
                return res.status(400).json({
                    success: false,
                    error: 'Device already registered'
                });
            }

            // Test connection before saving
            const testApi = new MikroTikAPI({
                host: vpnIpAddress,
                user: apiUsername,
                password: apiPassword
            });

            try {
                await testApi.connect();
                const systemInfo = await testApi.getSystemInfo();
                await testApi.disconnect();

                // Create device
                const device = await Device.create({
                    organization: req.user.organization,
                    name,
                    serialNumber,
                    macAddress: macAddress.toUpperCase(),
                    model: model || systemInfo.platform,
                    firmwareVersion: systemInfo.version,
                    location,
                    vpnIpAddress,
                    configuration: {
                        apiUsername,
                        apiPassword: this.encryptPassword(apiPassword)
                    },
                    status: 'online',
                    lastSeen: new Date()
                });

                // Store connection
                this.connections.set(device._id.toString(), testApi);

                res.status(201).json({
                    success: true,
                    data: device
                });

                // Emit device registered event
                req.app.get('io').to(`org:${req.user.organization}`).emit('device:registered', {
                    device: device.toObject()
                });

            } catch (error) {
                return res.status(400).json({
                    success: false,
                    error: `Failed to connect to device: ${error.message}`
                });
            }
        } catch (error) {
            next(error);
        }
    }

    // Update device
    async updateDevice(req, res, next) {
        try {
            const device = await Device.findOneAndUpdate(
                {
                    _id: req.params.id,
                    organization: req.user.organization
                },
                req.body,
                {
                    new: true,
                    runValidators: true
                }
            );

            if (!device) {
                return res.status(404).json({
                    success: false,
                    error: 'Device not found'
                });
            }

            res.json({
                success: true,
                data: device
            });

            // Emit device updated event
            req.app.get('io').to(`org:${req.user.organization}`).emit('device:updated', {
                device: device.toObject()
            });
        } catch (error) {
            next(error);
        }
    }

    // Delete device
    async deleteDevice(req, res, next) {
        try {
            const device = await Device.findOneAndDelete({
                _id: req.params.id,
                organization: req.user.organization
            });

            if (!device) {
                return res.status(404).json({
                    success: false,
                    error: 'Device not found'
                });
            }

            // Close connection if exists
            const connectionKey = device._id.toString();
            if (this.connections.has(connectionKey)) {
                const api = this.connections.get(connectionKey);
                await api.disconnect();
                this.connections.delete(connectionKey);
            }

            res.json({
                success: true,
                data: {}
            });

            // Emit device deleted event
            req.app.get('io').to(`org:${req.user.organization}`).emit('device:deleted', {
                deviceId: device._id
            });
        } catch (error) {
            next(error);
        }
    }

    // Discover devices on network
    async discoverDevices(req, res, next) {
        try {
            const { network } = req.body;

            let devices = [];
            
            if (network) {
                // Scan specific network
                devices = await this.discovery.scanNetwork(network);
            } else {
                // Broadcast discovery
                devices = await this.discovery.discover();
            }

            // Filter out already registered devices
            const registeredDevices = await Device.find({
                organization: req.user.organization,
                macAddress: { $in: devices.map(d => d.macAddress?.toUpperCase()).filter(Boolean) }
            });

            const registeredMacs = new Set(registeredDevices.map(d => d.macAddress));
            const newDevices = devices.filter(d => 
                d.macAddress && !registeredMacs.has(d.macAddress.toUpperCase())
            );

            res.json({
                success: true,
                data: {
                    discovered: devices.length,
                    new: newDevices.length,
                    devices: newDevices
                }
            });
        } catch (error) {
            next(error);
        }
    }

    // Execute command on device
    async executeCommand(req, res, next) {
        try {
            const { command, params } = req.body;

            const device = await Device.findOne({
                _id: req.params.id,
                organization: req.user.organization
            });

            if (!device) {
                return res.status(404).json({
                    success: false,
                    error: 'Device not found'
                });
            }

            const api = await this.getDeviceConnection(device);
            const result = await api.execute(command, params);

            res.json({
                success: true,
                data: result
            });

            // Log command execution
            logger.info(`Command executed on device ${device.name}: ${command}`, {
                deviceId: device._id,
                command,
                params,
                user: req.user._id
            });
        } catch (error) {
            next(error);
        }
    }

    // Get device statistics
    async getDeviceStats(req, res, next) {
        try {
            const device = await Device.findOne({
                _id: req.params.id,
                organization: req.user.organization
            });

            if (!device) {
                return res.status(404).json({
                    success: false,
                    error: 'Device not found'
                });
            }

            const api = await this.getDeviceConnection(device);
            
            const [systemInfo, interfaces, hotspotActive, queues] = await Promise.all([
                api.getSystemInfo(),
                api.getInterfaces(),
                api.getHotspotActive(),
                api.getQueues()
            ]);

            res.json({
                success: true,
                data: {
                    system: systemInfo,
                    interfaces,
                    hotspot: {
                        activeUsers: hotspotActive.length,
                        sessions: hotspotActive
                    },
                    queues
                }
            });
        } catch (error) {
            next(error);
        }
    }

    // Backup device configuration
    async backupDevice(req, res, next) {
        try {
            const device = await Device.findOne({
                _id: req.params.id,
                organization: req.user.organization
            });

            if (!device) {
                return res.status(404).json({
                    success: false,
                    error: 'Device not found'
                });
            }

            const api = await this.getDeviceConnection(device);
            
            // Create backup
            const backupName = `backup-${device.name}-${Date.now()}`;
            await api.createBackup(backupName);

            // Export configuration
            const configuration = await api.exportConfiguration();

            // Store backup info in database
            device.backups = device.backups || [];
            device.backups.push({
                filename: backupName,
                createdAt: new Date(),
                createdBy: req.user._id,
                size: Buffer.byteLength(configuration),
                configuration
            });

            // Keep only last 10 backups
            if (device.backups.length > 10) {
                device.backups = device.backups.slice(-10);
            }

            await device.save();

            res.json({
                success: true,
                data: {
                    filename: backupName,
                    size: Buffer.byteLength(configuration),
                    createdAt: new Date()
                }
            });
        } catch (error) {
            next(error);
        }
    }

    // Reboot device
    async rebootDevice(req, res, next) {
        try {
            const device = await Device.findOne({
                _id: req.params.id,
                organization: req.user.organization
            });

            if (!device) {
                return res.status(404).json({
                    success: false,
                    error: 'Device not found'
                });
            }

            const api = await this.getDeviceConnection(device);
            await api.reboot();

            // Update device status
            device.status = 'maintenance';
            device.alerts.push({
                type: 'warning',
                message: 'Device is rebooting',
                timestamp: new Date()
            });
            await device.save();

            res.json({
                success: true,
                message: 'Device reboot initiated'
            });

            // Emit reboot event
            req.app.get('io').to(`org:${req.user.organization}`).emit('device:rebooting', {
                deviceId: device._id,
                deviceName: device.name
            });

            // Schedule status check in 2 minutes
            setTimeout(async () => {
                const isOnline = await this.checkDeviceStatus(device.vpnIpAddress);
                
                device.status = isOnline ? 'online' : 'offline';
                await device.save();

                req.app.get('io').to(`org:${req.user.organization}`).emit('device:status:update', {
                    deviceId: device._id,
                    status: device.status
                });
            }, 120000);

        } catch (error) {
            next(error);
        }
    }

    // Apply configuration template
    async applyTemplate(req, res, next) {
        try {
            const { templateId } = req.body;

            const device = await Device.findOne({
                _id: req.params.id,
                organization: req.user.organization
            });

            if (!device) {
                return res.status(404).json({
                    success: false,
                    error: 'Device not found'
                });
            }

            // Get template
            const ConfigTemplate = require('../models/ConfigTemplate');
            const template = await ConfigTemplate.findOne({
                _id: templateId,
                organization: req.user.organization
            });

            if (!template) {
                return res.status(404).json({
                    success: false,
                    error: 'Template not found'
                });
            }

            const api = await this.getDeviceConnection(device);

            // Apply template commands
            const results = [];
            for (const command of template.commands) {
                try {
                    const result = await api.execute(command.command, command.params);
                    results.push({
                        command: command.command,
                        success: true,
                        result
                    });
                } catch (error) {
                    results.push({
                        command: command.command,
                        success: false,
                        error: error.message
                    });
                }
            }

            // Update device configuration
            device.configuration.lastTemplate = templateId;
            device.configuration.lastTemplateApplied = new Date();
            await device.save();

            res.json({
                success: true,
                data: {
                    template: template.name,
                    results
                }
            });
        } catch (error) {
            next(error);
        }
    }

    // Helper methods
    async getDeviceConnection(device) {
        const connectionKey = device._id.toString();
        
        if (this.connections.has(connectionKey)) {
            const api = this.connections.get(connectionKey);
            if (api.isConnected) {
                return api;
            }
        }

        // Create new connection
        const api = new MikroTikAPI({
            host: device.vpnIpAddress,
            user: device.configuration.apiUsername,
            password: this.decryptPassword(device.configuration.apiPassword)
        });

        await api.connect();
        this.connections.set(connectionKey, api);

        // Set up event handlers
        api.on('disconnected', () => {
            this.connections.delete(connectionKey);
        });

        api.on('error', (error) => {
            logger.error(`Device connection error for ${device.name}: ${error.message}`);
        });

        return api;
    }

    async checkDeviceStatus(ipAddress) {
        const ping = require('ping');
        
        try {
            const result = await ping.promise.probe(ipAddress, {
                timeout: 2,
                min_reply: 1
            });
            
            return result.alive;
        } catch (error) {
            return false;
        }
    }

    encryptPassword(password) {
        // TODO: Implement proper encryption
        const crypto = require('crypto');
        const algorithm = 'aes-256-cbc';
        const key = crypto.scryptSync(process.env.ENCRYPTION_KEY || 'default-key', 'salt', 32);
        const iv = crypto.randomBytes(16);
        
        const cipher = crypto.createCipheriv(algorithm, key, iv);
        let encrypted = cipher.update(password, 'utf8', 'hex');
        encrypted += cipher.final('hex');
        
        return iv.toString('hex') + ':' + encrypted;
    }

    decryptPassword(encryptedPassword) {
        // Implement proper decryption
        const crypto = require('crypto');
        const algorithm = 'aes-256-cbc';
        const key = crypto.scryptSync(process.env.ENCRYPTION_KEY || 'default-key', 'salt', 32);
        
        try {
            const [ivHex, encrypted] = encryptedPassword.split(':');
            const iv = Buffer.from(ivHex, 'hex');
            
            const decipher = crypto.createDecipheriv(algorithm, key, iv);
            let decrypted = decipher.update(encrypted, 'hex', 'utf8');
            decrypted += decipher.final('utf8');
            
            return decrypted;
        } catch (error) {
            logger.error('Failed to decrypt password:', error);
            throw new Error('Decryption failed');
        }
    }
}

module.exports = new DeviceController();
EOF
}

# Create device monitoring service  
create_device_monitoring_service() {
    cat << 'EOF' > "$APP_DIR/src/mikrotik/lib/device-monitor.js"
const EventEmitter = require('events');
const schedule = require('node-schedule');
const Device = require('../../../models/Device');
const MikroTikAPI = require('./mikrotik-api');
const logger = require('../../../utils/logger');
const { sendAlert } = require('../../../utils/alerts');

class DeviceMonitor extends EventEmitter {
    constructor(io) {
        super();
        this.io = io;
        this.monitors = new Map();
        this.alerts = new Map();
        this.checkInterval = 60000; // 1 minute
        this.isRunning = false;
    }

    async start() {
        if (this.isRunning) {
            logger.warn('Device monitor is already running');
            return;
        }

        this.isRunning = true;
        logger.info('Starting device monitor...');

        // Initial check
        await this.checkAllDevices();

        // Schedule regular checks
        this.scheduleJob = schedule.scheduleJob('*/1 * * * *', async () => {
            await this.checkAllDevices();
        });

        // Schedule hourly statistics collection
        this.statsJob = schedule.scheduleJob('0 * * * *', async () => {
            await this.collectStatistics();
        });

        // Schedule daily health report
        this.reportJob = schedule.scheduleJob('0 8 * * *', async () => {
            await this.generateHealthReport();
        });

        this.emit('started');
    }

    async stop() {
        if (!this.isRunning) {
            return;
        }

        this.isRunning = false;
        logger.info('Stopping device monitor...');

        // Cancel scheduled jobs
        if (this.scheduleJob) {
            this.scheduleJob.cancel();
        }
        if (this.statsJob) {
            this.statsJob.cancel();
        }
        if (this.reportJob) {
            this.reportJob.cancel();
        }

        // Disconnect all monitors
        for (const [deviceId, monitor] of this.monitors) {
            if (monitor.api) {
                await monitor.api.disconnect();
            }
        }

        this.monitors.clear();
        this.alerts.clear();

        this.emit('stopped');
    }

    async checkAllDevices() {
        try {
            const devices = await Device.find({ isActive: true });
            
            for (const device of devices) {
                await this.checkDevice(device);
            }
        } catch (error) {
            logger.error(`Failed to check devices: ${error.message}`);
        }
    }

    async checkDevice(device) {
        const deviceId = device._id.toString();
        
        try {
            // Check if device is reachable
            const ping = require('ping');
            const pingResult = await ping.promise.probe(device.vpnIpAddress, {
                timeout: 5,
                min_reply: 1
            });

            if (pingResult.alive) {
                // Device is online
                await this.handleDeviceOnline(device);
            } else {
                // Device is offline
                await this.handleDeviceOffline(device);
            }
        } catch (error) {
            logger.error(`Failed to check device ${device.name}: ${error.message}`);
            await this.handleDeviceError(device, error);
        }
    }

    async handleDeviceOnline(device) {
        const deviceId = device._id.toString();
        const wasOffline = device.status === 'offline';

        // Update device status
        device.status = 'online';
        device.lastSeen = new Date();

        // Clear offline alert if exists
        if (this.alerts.has(deviceId)) {
            const alert = this.alerts.get(deviceId);
            if (alert.type === 'offline') {
                this.alerts.delete(deviceId);
                
                // Send recovery notification
                if (wasOffline) {
                    await sendAlert({
                        type: 'recovery',
                        device: device.name,
                        message: `Device ${device.name} is back online`,
                        timestamp: new Date()
                    });
                }
            }
        }

        // Get device metrics
        try {
            const monitor = await this.getDeviceMonitor(device);
            const metrics = await this.collectDeviceMetrics(monitor.api);
            
            // Update device health
            device.health = {
                cpuUsage: metrics.system.cpuLoad,
                memoryUsage: Math.round((1 - metrics.system.freeMemory / metrics.system.totalMemory) * 100),
                diskUsage: Math.round((1 - metrics.system.freeHddSpace / metrics.system.totalHddSpace) * 100),
                temperature: metrics.system.temperature,
                uptime: metrics.system.uptime
            };

            // Check for health alerts
            await this.checkHealthAlerts(device, metrics);

            // Update VPN status
            device.vpnStatus = {
                connected: true,
                connectedAt: device.vpnStatus.connectedAt || new Date(),
                bytesIn: metrics.traffic.bytesIn,
                bytesOut: metrics.traffic.bytesOut
            };

            // Emit real-time update
            this.io.to(`org:${device.organization}`).emit('device:metrics', {
                deviceId: device._id,
                metrics,
                timestamp: new Date()
            });

        } catch (error) {
            logger.error(`Failed to collect metrics for ${device.name}: ${error.message}`);
        }

        await device.save();
    }

    async handleDeviceOffline(device) {
        const deviceId = device._id.toString();
        const wasOnline = device.status === 'online';

        // Update device status
        device.status = 'offline';
        device.vpnStatus.connected = false;
        device.vpnStatus.disconnectedAt = new Date();

        // Create offline alert
        if (!this.alerts.has(deviceId) && wasOnline) {
            const alert = {
                type: 'offline',
                device: device.name,
                message: `Device ${device.name} is offline`,
                timestamp: new Date(),
                notificationSent: false
            };

            this.alerts.set(deviceId, alert);

            // Send immediate notification for critical devices
            if (device.tags.includes('critical')) {
                await sendAlert(alert);
                alert.notificationSent = true;
            } else {
                // Schedule notification after 5 minutes
                setTimeout(async () => {
                    if (this.alerts.has(deviceId) && !alert.notificationSent) {
                        await sendAlert(alert);
                        alert.notificationSent = true;
                    }
                }, 300000);
            }
        }

        // Add alert to device
        device.alerts.push({
            type: 'error',
            message: 'Device is offline',
            timestamp: new Date()
        });

        // Keep only last 50 alerts
        if (device.alerts.length > 50) {
            device.alerts = device.alerts.slice(-50);
        }

        await device.save();

        // Emit offline event
        this.io.to(`org:${device.organization}`).emit('device:offline', {
            deviceId: device._id,
            deviceName: device.name,
            timestamp: new Date()
        });
    }

    async handleDeviceError(device, error) {
        device.status = 'error';
        device.alerts.push({
            type: 'critical',
            message: `Connection error: ${error.message}`,
            timestamp: new Date()
        });

        await device.save();

        // Send critical alert
        await sendAlert({
            type: 'critical',
            device: device.name,
            message: `Critical error on device ${device.name}: ${error.message}`,
            timestamp: new Date()
        });
    }

    async getDeviceMonitor(device) {
        const deviceId = device._id.toString();

        if (this.monitors.has(deviceId)) {
            const monitor = this.monitors.get(deviceId);
            if (monitor.api && monitor.api.isConnected) {
                return monitor;
            }
        }

        // Create new monitor
        const api = new MikroTikAPI({
            host: device.vpnIpAddress,
            user: device.configuration.apiUsername,
            password: this.decryptPassword(device.configuration.apiPassword)
        });

        await api.connect();

        const monitor = {
            device,
            api,
            lastCheck: new Date()
        };

        this.monitors.set(deviceId, monitor);

        // Set up API event handlers
        api.on('disconnected', () => {
            this.monitors.delete(deviceId);
        });

        api.on('error', (error) => {
            logger.error(`Monitor API error for ${device.name}: ${error.message}`);
        });

        return monitor;
    }

    async collectDeviceMetrics(api) {
        const [system, interfaces, hotspotActive, queues, logs] = await Promise.all([
            api.getSystemInfo(),
            api.getInterfaces(),
            api.getHotspotActive(),
            api.getQueues(),
            api.getSystemLogs(50)
        ]);

        // Calculate interface traffic
        const traffic = interfaces.reduce((acc, iface) => {
            acc.bytesIn += iface.stats.rxBytes || 0;
            acc.bytesOut += iface.stats.txBytes || 0;
            acc.packetsIn += iface.stats.rxPackets || 0;
            acc.packetsOut += iface.stats.txPackets || 0;
            acc.errors += (iface.stats.rxErrors || 0) + (iface.stats.txErrors || 0);
            return acc;
        }, {
            bytesIn: 0,
            bytesOut: 0,
            packetsIn: 0,
            packetsOut: 0,
            errors: 0
        });

        // Parse temperature if available
        let temperature = null;
        if (system.health && system.health.length > 0) {
            const tempReading = system.health.find(h => h.name === 'temperature');
            if (tempReading) {
                temperature = parseFloat(tempReading.value);
            }
        }

        return {
            system: {
                ...system,
                temperature
            },
            interfaces,
            hotspot: {
                activeUsers: hotspotActive.length,
                sessions: hotspotActive
            },
            queues,
            traffic,
            logs: logs.slice(0, 10) // Last 10 log entries
        };
    }

    async checkHealthAlerts(device, metrics) {
        const alerts = [];

        // CPU usage alert
        if (metrics.system.cpuLoad > 80) {
            alerts.push({
                type: 'warning',
                message: `High CPU usage: ${metrics.system.cpuLoad}%`,
                metric: 'cpu',
                value: metrics.system.cpuLoad
            });
        }

        // Memory usage alert
        const memoryUsage = Math.round((1 - metrics.system.freeMemory / metrics.system.totalMemory) * 100);
        if (memoryUsage > 85) {
            alerts.push({
                type: 'warning',
                message: `High memory usage: ${memoryUsage}%`,
                metric: 'memory',
                value: memoryUsage
            });
        }

        // Disk usage alert
        const diskUsage = Math.round((1 - metrics.system.freeHddSpace / metrics.system.totalHddSpace) * 100);
        if (diskUsage > 90) {
            alerts.push({
                type: 'critical',
                message: `Critical disk usage: ${diskUsage}%`,
                metric: 'disk',
                value: diskUsage
            });
        }

        // Temperature alert
        if (metrics.system.temperature && metrics.system.temperature > 70) {
            alerts.push({
                type: 'warning',
                message: `High temperature: ${metrics.system.temperature}°C`,
                metric: 'temperature',
                value: metrics.system.temperature
            });
        }

        // Interface errors alert
        if (metrics.traffic.errors > 100) {
            alerts.push({
                type: 'warning',
                message: `High interface errors: ${metrics.traffic.errors}`,
                metric: 'errors',
                value: metrics.traffic.errors
            });
        }

        // Process alerts
        for (const alert of alerts) {
            const alertKey = `${device._id}-${alert.metric}`;
            
            if (!this.alerts.has(alertKey)) {
                // New alert
                this.alerts.set(alertKey, {
                    ...alert,
                    device: device.name,
                    deviceId: device._id,
                    timestamp: new Date(),
                    notificationSent: false
                });

                // Add to device alerts
                device.alerts.push({
                    type: alert.type,
                    message: alert.message,
                    timestamp: new Date()
                });

                // Send notification for critical alerts
                if (alert.type === 'critical') {
                    await sendAlert({
                        ...alert,
                        device: device.name
                    });
                }
            }
        }

        // Clear resolved alerts
        for (const [alertKey, alert] of this.alerts) {
            if (alertKey.startsWith(device._id.toString())) {
                const metric = alertKey.split('-')[1];
                const currentAlert = alerts.find(a => a.metric === metric);
                
                if (!currentAlert) {
                    // Alert resolved
                    this.alerts.delete(alertKey);
                    
                    // Mark device alert as resolved
                    const deviceAlert = device.alerts.find(a => 
                        a.message.includes(metric) && !a.resolved
                    );
                    if (deviceAlert) {
                        deviceAlert.resolved = true;
                    }
                }
            }
        }
    }

    async collectStatistics() {
        logger.info('Collecting hourly statistics...');

        try {
            const devices = await Device.find({ isActive: true });

            for (const device of devices) {
                try {
                    const monitor = await this.getDeviceMonitor(device);
                    const metrics = await this.collectDeviceMetrics(monitor.api);

                    // Store statistics
                    const DeviceStatistics = require('../../../models/DeviceStatistics');
                    await DeviceStatistics.create({
                        device: device._id,
                        timestamp: new Date(),
                        system: {
                            cpuLoad: metrics.system.cpuLoad,
                            memoryUsage: Math.round((1 - metrics.system.freeMemory / metrics.system.totalMemory) * 100),
                            diskUsage: Math.round((1 - metrics.system.freeHddSpace / metrics.system.totalHddSpace) * 100),
                            temperature: metrics.system.temperature,
                            uptime: metrics.system.uptime
                        },
                        traffic: metrics.traffic,
                        hotspot: {
                            activeUsers: metrics.hotspot.activeUsers
                        }
                    });

                    logger.info(`Statistics collected for device ${device.name}`);
                } catch (error) {
                    logger.error(`Failed to collect statistics for ${device.name}: ${error.message}`);
                }
            }
        } catch (error) {
            logger.error(`Failed to collect statistics: ${error.message}`);
        }
    }

    async generateHealthReport() {
        logger.info('Generating daily health report...');

        try {
            const Organization = require('../../../models/Organization');
            const organizations = await Organization.find({ isActive: true });

            for (const org of organizations) {
                const devices = await Device.find({ 
                    organization: org._id,
                    isActive: true 
                });

                const report = {
                    organization: org.name,
                    date: new Date(),
                    totalDevices: devices.length,
                    onlineDevices: devices.filter(d => d.status === 'online').length,
                    offlineDevices: devices.filter(d => d.status === 'offline').length,
                    alerts: [],
                    deviceHealth: []
                };

                // Collect device health
                for (const device of devices) {
                    const health = {
                        name: device.name,
                        status: device.status,
                        uptime: device.health?.uptime,
                        cpuAvg: 0,
                        memoryAvg: 0,
                        diskUsage: device.health?.diskUsage,
                        activeAlerts: device.alerts.filter(a => !a.resolved).length
                    };

                    // Get average metrics from last 24 hours
                    const DeviceStatistics = require('../../../models/DeviceStatistics');
                    const stats = await DeviceStatistics.find({
                        device: device._id,
                        timestamp: { $gte: new Date(Date.now() - 86400000) }
                    });

                    if (stats.length > 0) {
                        health.cpuAvg = Math.round(
                            stats.reduce((sum, s) => sum + s.system.cpuLoad, 0) / stats.length
                        );
                        health.memoryAvg = Math.round(
                            stats.reduce((sum, s) => sum + s.system.memoryUsage, 0) / stats.length
                        );
                    }

                    report.deviceHealth.push(health);

                    // Collect active alerts
                    const activeAlerts = device.alerts.filter(a => !a.resolved);
                    report.alerts.push(...activeAlerts.map(a => ({
                        device: device.name,
                        ...a
                    })));
                }

                // Send report
                await this.sendHealthReport(org, report);
            }
        } catch (error) {
            logger.error(`Failed to generate health report: ${error.message}`);
        }
    }

    async sendHealthReport(organization, report) {
        // TODO: Implement email sending
        logger.info(`Health report generated for ${organization.name}`);
        
        // For now, just emit via socket
        this.io.to(`org:${organization._id}`).emit('health:report', report);
    }

    decryptPassword(encryptedPassword) {
        // Implement proper decryption
        const crypto = require('crypto');
        const algorithm = 'aes-256-cbc';
        const key = crypto.scryptSync(process.env.ENCRYPTION_KEY || 'default-key', 'salt', 32);
        
        try {
            const [ivHex, encrypted] = encryptedPassword.split(':');
            const iv = Buffer.from(ivHex, 'hex');
            
            const decipher = crypto.createDecipheriv(algorithm, key, iv);
            let decrypted = decipher.update(encrypted, 'hex', 'utf8');
            decrypted += decipher.final('utf8');
            
            return decrypted;
        } catch (error) {
            logger.error('Failed to decrypt password:', error);
            throw new Error('Decryption failed');
        }
    }
}

module.exports = DeviceMonitor;
EOF
}

# Create MikroTik script templates
create_mikrotik_templates() {
    # Hotspot setup template
    cat << 'EOF' > "$APP_DIR/src/mikrotik/templates/hotspot-setup.rsc"
# MikroTik Hotspot Setup Template
# Generated by MikroTik VPN Management System

# Set identity
/system identity set name="{{DEVICE_NAME}}"

# Configure hotspot interface
/interface bridge
add name=bridge-hotspot comment="Hotspot Bridge"

# Add hotspot interfaces to bridge
/interface bridge port
add bridge=bridge-hotspot interface={{HOTSPOT_INTERFACE}}

# Configure IP address for hotspot
/ip address
add address={{HOTSPOT_IP}}/24 interface=bridge-hotspot

# Configure DHCP server
/ip pool
add name=hotspot-pool ranges={{DHCP_RANGE}}

/ip dhcp-server
add address-pool=hotspot-pool disabled=no interface=bridge-hotspot name=hotspot-dhcp

/ip dhcp-server network
add address={{HOTSPOT_NETWORK}}/24 gateway={{HOTSPOT_IP}} dns-server=8.8.8.8,8.8.4.4

# Configure hotspot
/ip hotspot profile
add dns-name={{HOTSPOT_DNS_NAME}} hotspot-address={{HOTSPOT_IP}} name={{PROFILE_NAME}} \
    login-by=cookie,http-chap,trial use-radius=no

/ip hotspot
add address-pool=hotspot-pool disabled=no interface=bridge-hotspot name={{HOTSPOT_NAME}} \
    profile={{PROFILE_NAME}}

# Configure hotspot user profile
/ip hotspot user profile
add name="default" shared-users=1 rate-limit="2M/2M"
add name="premium" shared-users=1 rate-limit="5M/5M"
add name="vip" shared-users=2 rate-limit="10M/10M"

# Configure firewall for hotspot
/ip firewall filter
add chain=input action=accept protocol=tcp dst-port=80,443,8291 src-address={{HOTSPOT_NETWORK}}/24 \
    comment="Allow hotspot management"
add chain=forward action=accept src-address={{HOTSPOT_NETWORK}}/24 out-interface={{WAN_INTERFACE}} \
    comment="Allow hotspot to internet"

# Configure NAT
/ip firewall nat
add chain=srcnat action=masquerade src-address={{HOTSPOT_NETWORK}}/24 out-interface={{WAN_INTERFACE}} \
    comment="Hotspot NAT"

# Configure walled garden (optional)
/ip hotspot walled-garden
add dst-host="*.google.com" comment="Allow Google"
add dst-host="*.facebook.com" comment="Allow Facebook"

# Configure hotspot pages
/ip hotspot profile
set [find name={{PROFILE_NAME}}] \
    html-directory=flash/hotspot \
    login-by=cookie,http-chap,trial

# Create default trial user
/ip hotspot user
add name="trial" profile="default" limit-uptime=30m comment="30-minute trial"

# Configure logging
/system logging
add topics=hotspot,info action=memory
add topics=hotspot,error action=memory

print "Hotspot setup completed successfully!"
EOF

    # VPN client setup template
    cat << 'EOF' > "$APP_DIR/src/mikrotik/templates/vpn-client-setup.rsc"
# MikroTik VPN Client Setup Template
# Connect to Management VPN Server

# Configure L2TP client
/interface l2tp-client
add connect-to={{VPN_SERVER}} name=vpn-mgmt user={{VPN_USER}} \
    password={{VPN_PASSWORD}} profile=default-encryption \
    add-default-route=no disabled=no comment="Management VPN"

# Wait for connection
:delay 5s

# Add route to management network
/ip route
add dst-address={{MGMT_NETWORK}}/24 gateway=vpn-mgmt

# Configure firewall to allow management access
/ip firewall filter
add chain=input action=accept protocol=tcp dst-port=8728,8729,80,443,22 \
    src-address={{MGMT_NETWORK}}/24 comment="Allow management access"

# Enable API service
/ip service
set api disabled=no port=8728
set api-ssl disabled=no port=8729 certificate=api-ssl

# Configure API user
/user
add name={{API_USER}} password={{API_PASSWORD}} group=full \
    comment="API user for management system"

# Configure scheduled keepalive
/system scheduler
add name=vpn-keepalive interval=1m on-event="/ping {{VPN_SERVER}} count=3" \
    comment="Keep VPN connection alive"

print "VPN client setup completed successfully!"
EOF

    # Bandwidth management template
    cat << 'EOF' > "$APP_DIR/src/mikrotik/templates/bandwidth-management.rsc"
# MikroTik Bandwidth Management Template
# Configure QoS and bandwidth limits

# Create mangle rules for traffic marking
/ip firewall mangle
add chain=forward action=mark-connection new-connection-mark=hotspot-conn \
    src-address={{HOTSPOT_NETWORK}}/24 passthrough=yes comment="Mark hotspot connections"
add chain=forward action=mark-packet new-packet-mark=hotspot-packet \
    connection-mark=hotspot-conn passthrough=no comment="Mark hotspot packets"

# Create PCQ types for fair bandwidth distribution
/queue type
add name=pcq-download kind=pcq pcq-classifier=dst-address pcq-rate={{DOWNLOAD_RATE}}
add name=pcq-upload kind=pcq pcq-classifier=src-address pcq-rate={{UPLOAD_RATE}}

# Create queue tree for bandwidth management
/queue tree
add name=download parent=global packet-mark=hotspot-packet queue=pcq-download \
    max-limit={{TOTAL_DOWNLOAD}} comment="Total download bandwidth"
add name=upload parent=global packet-mark=hotspot-packet queue=pcq-upload \
    max-limit={{TOTAL_UPLOAD}} comment="Total upload bandwidth"

# Create simple queues for user profiles
/queue simple
add name="default-profile" target={{HOTSPOT_NETWORK}}/24 \
    max-limit={{DEFAULT_UP}}/{{DEFAULT_DOWN}} burst-limit={{DEFAULT_BURST_UP}}/{{DEFAULT_BURST_DOWN}} \
    burst-time=10s/10s burst-threshold={{DEFAULT_THRESHOLD_UP}}/{{DEFAULT_THRESHOLD_DOWN}} \
    comment="Default user profile limits"

# Configure queue priorities
/queue tree
add name=priority-high parent=download packet-mark=priority-high priority=1 queue=default
add name=priority-normal parent=download packet-mark=priority-normal priority=4 queue=default
add name=priority-low parent=download packet-mark=priority-low priority=8 queue=default

print "Bandwidth management configured successfully!"
EOF

    # Security hardening template
    cat << 'EOF' > "$APP_DIR/src/mikrotik/templates/security-hardening.rsc"
# MikroTik Security Hardening Template
# Implement security best practices

# Disable unnecessary services
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set ssh port=22222 disabled=no
set api disabled=no address={{MGMT_NETWORK}}/24
set api-ssl disabled=no address={{MGMT_NETWORK}}/24 certificate=api-ssl
set winbox disabled=no address={{MGMT_NETWORK}}/24

# Configure strong passwords policy
/user
set [find name=admin] password={{ADMIN_PASSWORD}}

# Remove default user if exists
/user remove [find name=admin !default]

# Configure firewall - Input chain
/ip firewall filter
add chain=input action=accept connection-state=established,related \
    comment="Accept established/related"
add chain=input action=accept protocol=icmp comment="Accept ICMP"
add chain=input action=accept dst-port=8728,8729,22222 protocol=tcp \
    src-address={{MGMT_NETWORK}}/24 comment="Accept management"
add chain=input action=accept in-interface=bridge-hotspot dst-port=53 protocol=udp \
    comment="Accept DNS from hotspot"
add chain=input action=drop comment="Drop everything else"

# Configure firewall - Forward chain
/ip firewall filter
add chain=forward action=accept connection-state=established,related \
    comment="Accept established/related"
add chain=forward action=accept src-address={{HOTSPOT_NETWORK}}/24 \
    out-interface={{WAN_INTERFACE}} comment="Allow hotspot to internet"
add chain=forward action=drop connection-state=invalid comment="Drop invalid"
add chain=forward action=drop comment="Drop everything else"

# Configure port knocking (optional)
/ip firewall filter
add chain=input action=add-src-to-address-list address-list=knock-step1 \
    address-list-timeout=10s dst-port=1111 protocol=tcp comment="Port knock step 1"
add chain=input action=add-src-to-address-list address-list=knock-step2 \
    address-list-timeout=10s dst-port=2222 protocol=tcp src-address-list=knock-step1
add chain=input action=add-src-to-address-list address-list=secure-access \
    address-list-timeout=1h dst-port=3333 protocol=tcp src-address-list=knock-step2
add chain=input action=accept dst-port=8291 protocol=tcp src-address-list=secure-access \
    comment="Allow WinBox after port knocking"

# Configure DDoS protection
/ip firewall filter
add chain=input action=drop connection-limit=50,32 protocol=tcp comment="Limit connections"
add chain=input action=drop src-address-list=blacklist comment="Drop blacklisted"
add chain=input action=add-src-to-address-list address-list=blacklist \
    address-list-timeout=1d connection-state=new connection-limit=100,32 protocol=tcp \
    comment="Blacklist excessive connections"

# Enable secure neighbor discovery
/ip neighbor discovery-settings
set discover-interface-list=none

# Configure NTP
/system ntp client
set enabled=yes server-dns-names=pool.ntp.org

# Configure logging
/system logging
add topics=firewall,warning action=memory
add topics=system,error,critical action=memory

print "Security hardening completed successfully!"
EOF

    log "MikroTik templates created"
}

# Create additional models that will be needed
create_device_statistics_model() {
    cat << 'EOF' > "$APP_DIR/models/DeviceStatistics.js"
const mongoose = require('mongoose');

const deviceStatisticsSchema = new mongoose.Schema({
    device: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Device',
        required: true,
        index: true
    },
    timestamp: {
        type: Date,
        default: Date.now,
        index: true
    },
    system: {
        cpuLoad: Number,
        memoryUsage: Number,
        diskUsage: Number,
        temperature: Number,
        uptime: String
    },
    traffic: {
        bytesIn: Number,
        bytesOut: Number,
        packetsIn: Number,
        packetsOut: Number,
        errors: Number
    },
    hotspot: {
        activeUsers: Number,
        totalSessions: Number
    },
    interfaces: [{
        name: String,
        status: String,
        rxBytes: Number,
        txBytes: Number,
        rxErrors: Number,
        txErrors: Number
    }]
}, {
    timestamps: false
});

// Indexes for efficient queries
deviceStatisticsSchema.index({ device: 1, timestamp: -1 });
deviceStatisticsSchema.index({ timestamp: 1 }, { expireAfterSeconds: 2592000 }); // 30 days

module.exports = mongoose.model('DeviceStatistics', deviceStatisticsSchema);
EOF
}

# Create ConfigTemplate model
create_config_template_model() {
    cat << 'EOF' > "$APP_DIR/models/ConfigTemplate.js"
const mongoose = require('mongoose');

const configTemplateSchema = new mongoose.Schema({
    organization: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Organization',
        required: true,
        index: true
    },
    name: {
        type: String,
        required: true,
        trim: true
    },
    description: String,
    type: {
        type: String,
        enum: ['hotspot', 'vpn', 'firewall', 'qos', 'general'],
        required: true
    },
    commands: [{
        order: Number,
        command: String,
        params: mongoose.Schema.Types.Mixed,
        description: String
    }],
    variables: [{
        name: String,
        description: String,
        type: {
            type: String,
            enum: ['string', 'number', 'ip', 'network', 'interface']
        },
        defaultValue: mongoose.Schema.Types.Mixed,
        required: Boolean
    }],
    tags: [String],
    isActive: {
        type: Boolean,
        default: true
    },
    createdBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    }
}, {
    timestamps: true
});

module.exports = mongoose.model('ConfigTemplate', configTemplateSchema);
EOF
}

# Create utils/logger.js if not exists
create_logger_util() {
    mkdir -p "$APP_DIR/utils"
    
    cat << 'EOF' > "$APP_DIR/utils/logger.js"
const winston = require('winston');
const path = require('path');

const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.splat(),
        winston.format.json()
    ),
    defaultMeta: { service: 'mikrotik-vpn' },
    transports: [
        new winston.transports.Console({
            format: winston.format.combine(
                winston.format.colorize(),
                winston.format.simple()
            )
        }),
        new winston.transports.File({ 
            filename: path.join('/var/log/mikrotik-vpn', 'error.log'), 
            level: 'error' 
        }),
        new winston.transports.File({ 
            filename: path.join('/var/log/mikrotik-vpn', 'combined.log') 
        })
    ]
});

module.exports = logger;
EOF
}

# Create utils/alerts.js
create_alerts_util() {
    cat << 'EOF' > "$APP_DIR/utils/alerts.js"
const logger = require('./logger');

async function sendAlert(alert) {
    try {
        // Log the alert
        logger.warn('Alert:', alert);
        
        // TODO: Implement actual alert sending (email, Slack, etc.)
        // For now, just log it
        
        // Email implementation placeholder
        if (process.env.ALERT_EMAIL_ENABLED === 'true') {
            // const emailService = require('./email');
            // await emailService.sendAlert(alert);
        }
        
        // Slack implementation placeholder
        if (process.env.SLACK_WEBHOOK_URL) {
            // const { IncomingWebhook } = require('@slack/webhook');
            // const webhook = new IncomingWebhook(process.env.SLACK_WEBHOOK_URL);
            // await webhook.send({
            //     text: `Alert: ${alert.message}`,
            //     attachments: [{
            //         color: alert.type === 'critical' ? 'danger' : 'warning',
            //         fields: [
            //             { title: 'Device', value: alert.device, short: true },
            //             { title: 'Type', value: alert.type, short: true },
            //             { title: 'Time', value: alert.timestamp, short: true }
            //         ]
            //     }]
            // });
        }
        
        return true;
    } catch (error) {
        logger.error('Failed to send alert:', error);
        return false;
    }
}

module.exports = { sendAlert };
EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log "Starting Phase 2 Part 1: Core Setup and Device Management"
    log "======================================================"
    
    # Check prerequisites
    if [[ ! -d "$SYSTEM_DIR" ]]; then
        log_error "Phase 1 not completed. Please run Phase 1 installation first."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker ps &>/dev/null; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Create necessary utils
    create_logger_util
    create_alerts_util
    
    # Create additional models
    create_device_statistics_model
    create_config_template_model
    
    # Execute Phase 2.1
    phase2_1_device_management || {
        log_error "Phase 2.1 failed"
        exit 1
    }
    
    log "======================================"
    log "Phase 2 Part 1 completed successfully!"
    log ""
    log "Device Management components installed:"
    log "- MikroTik API wrapper"
    log "- Device discovery service"
    log "- Device controller"
    log "- Device monitoring service"
    log "- MikroTik script templates"
    log ""
    log "Continue with Part 2 for Hotspot Management..."
}

# Execute main function
main "$@"
