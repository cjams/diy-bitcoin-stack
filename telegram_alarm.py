#!/usr/bin/env python3
import subprocess
import time
import requests
import json
import os
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("telegram_alarm.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuration
CONFIG_FILE = 'config.json'

def load_config():
    """Load configuration from config.json file."""
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        logger.error(f"Configuration file {CONFIG_FILE} not found.")
        exit(1)
    except json.JSONDecodeError:
        logger.error(f"Error parsing {CONFIG_FILE}. Make sure it's valid JSON.")
        exit(1)

def send_telegram_message(bot_token, chat_id, message):
    """Send a message via Telegram bot."""
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    data = {
        "chat_id": chat_id,
        "text": message,
        "parse_mode": "Markdown"
    }
    
    try:
        response = requests.post(url, data=data)
        response.raise_for_status()
        logger.info("Telegram message sent successfully")
        return True
    except requests.exceptions.RequestException as e:
        logger.error(f"Error sending Telegram message: {e}")
        return False

def systemd_service_is_active(service_name):
    """Check if a systemd service is active."""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', service_name],
            capture_output=True,
            text=True,
            check=False
        )
        return result.stdout.strip() == 'active'
    except Exception as e:
        logger.error(f"Error checking service status: {e}")
        return False

def init_mullvad_checks(bot_token, chat_id):
    """Initialize Mullvad VPN status monitoring.
    
    Runs 'mullvad status' command and parses the output to extract:
    - Wireguard endpoint (e.g., us-lax-wg-101)
    - Location (e.g., Los Angeles, CA, USA)
    - IPv4 address
    - IPv6 address
    
    Returns a dictionary with the current status.
    """
    try:
        # Run 'mullvad status' command
        result = subprocess.run(
            ['mullvad', 'status'],
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode != 0:
            logger.error(f"Error running 'mullvad status': {result.stderr}")
            return None
        
        output = result.stdout.strip()
        logger.info(f"Mullvad status: {output}")
        
        # Parse the output
        mullvad_state = {
            'connected': False,
            'endpoint': None,
            'location': None,
            'ipv4': None,
            'ipv6': None
        }
        
        # Check if connected
        if output.startswith("Connected to"):
            mullvad_state['connected'] = True
            
            # Extract endpoint and location from first line
            # Format: "Connected to us-lax-wg-101 in Los Angeles, CA, USA"
            first_line = output.split('\n')[0]
            endpoint_parts = first_line.split(' in ')
            if len(endpoint_parts) == 2:
                # Extract endpoint (e.g., us-lax-wg-101)
                mullvad_state['endpoint'] = endpoint_parts[0].replace('Connected to ', '')
                # Extract location (e.g., Los Angeles, CA, USA)
                mullvad_state['location'] = endpoint_parts[1]
            
            # Extract IP addresses from second line
            # Format: "Your connection appears to be from: USA, Los Angeles, CA. IPv4: <ipv4>, IPv6: <ipv6>"
            if len(output.split('\n')) > 1:
                second_line = output.split('\n')[1]
                
                # Extract IPv4
                ipv4_match = second_line.split('IPv4: ')
                if len(ipv4_match) > 1:
                    ipv4 = ipv4_match[1].split(',')[0].strip()
                    mullvad_state['ipv4'] = ipv4
                
                # Extract IPv6
                ipv6_match = second_line.split('IPv6: ')
                if len(ipv6_match) > 1:
                    ipv6 = ipv6_match[1].strip()
                    mullvad_state['ipv6'] = ipv6
        
        # Send initial status message
        status_message = f"🔔 *Mullvad VPN Monitoring Started*\n"
        if mullvad_state['connected']:
            status_message += f"Status: *Connected*\n"
            status_message += f"Endpoint: `{mullvad_state['endpoint']}`\n"
            status_message += f"Location: `{mullvad_state['location']}`\n"
            status_message += f"IPv4: `{mullvad_state['ipv4']}`\n"
            if mullvad_state['ipv6']:
                status_message += f"IPv6: `{mullvad_state['ipv6']}`\n"
        else:
            status_message += f"Status: *Disconnected*\n"
        
        status_message += f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
        
        send_telegram_message(bot_token, chat_id, status_message)
        
        return mullvad_state
    
    except Exception as e:
        logger.error(f"Error initializing Mullvad checks: {e}")
        return None

def check_mullvad_status(bot_token, chat_id, previous_state):
    """Check for changes in Mullvad VPN status.
    
    Compares the current Mullvad status with the previous state and
    sends notifications if there are any changes.
    
    Returns the updated state.
    """
    if previous_state is None:
        return init_mullvad_checks(bot_token, chat_id)
    
    try:
        # Run 'mullvad status' command
        result = subprocess.run(
            ['mullvad', 'status'],
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode != 0:
            logger.error(f"Error running 'mullvad status': {result.stderr}")
            return previous_state
        
        output = result.stdout.strip()
        
        # Parse the output
        current_state = {
            'connected': False,
            'endpoint': None,
            'location': None,
            'ipv4': None,
            'ipv6': None
        }
        
        # Check if connected
        if output.startswith("Connected to"):
            current_state['connected'] = True
            
            # Extract endpoint and location from first line
            first_line = output.split('\n')[0]
            endpoint_parts = first_line.split(' in ')
            if len(endpoint_parts) == 2:
                current_state['endpoint'] = endpoint_parts[0].replace('Connected to ', '')
                current_state['location'] = endpoint_parts[1]
            
            # Extract IP addresses from second line
            if len(output.split('\n')) > 1:
                second_line = output.split('\n')[1]
                
                # Extract IPv4
                ipv4_match = second_line.split('IPv4: ')
                if len(ipv4_match) > 1:
                    ipv4 = ipv4_match[1].split(',')[0].strip()
                    current_state['ipv4'] = ipv4
                
                # Extract IPv6
                ipv6_match = second_line.split('IPv6: ')
                if len(ipv6_match) > 1:
                    ipv6 = ipv6_match[1].strip()
                    current_state['ipv6'] = ipv6
        
        # Check for changes
        changes = []
        
        # Connection status change
        if current_state['connected'] != previous_state['connected']:
            if current_state['connected']:
                changes.append("🟢 VPN *Connected*")
            else:
                changes.append("🔴 VPN *Disconnected*")
        
        # Only check other changes if both states are connected
        if current_state['connected'] and previous_state['connected']:
            # Endpoint change
            if current_state['endpoint'] != previous_state['endpoint']:
                changes.append(f"🔄 Endpoint changed: `{previous_state['endpoint']}` → `{current_state['endpoint']}`")
            
            # Location change
            if current_state['location'] != previous_state['location']:
                changes.append(f"📍 Location changed: `{previous_state['location']}` → `{current_state['location']}`")
            
            # IPv4 change
            if current_state['ipv4'] != previous_state['ipv4']:
                changes.append(f"🌐 IPv4 changed: `{previous_state['ipv4']}` → `{current_state['ipv4']}`")
            
            # IPv6 change
            if current_state['ipv6'] != previous_state['ipv6']:
                changes.append(f"🌐 IPv6 changed: `{previous_state['ipv6']}` → `{current_state['ipv6']}`")
        
        # Send notification if there are changes
        if changes:
            message = f"🔔 *Mullvad VPN Status Change*\n"
            message += "\n".join(changes)
            message += f"\n\nTime: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
            
            send_telegram_message(bot_token, chat_id, message)
        
        return current_state
    
    except Exception as e:
        logger.error(f"Error checking Mullvad status: {e}")
        return previous_state

def init_systemd_checks(bot_token, chat_id, systemd_services_list):
    systemd_state = {}

    for s in systemd_services_list:
        active = systemd_service_is_active(s)
        systemd_state[s] = active

        status = "active" if active else "inactive"
        send_telegram_message(
            bot_token,
            chat_id,
            f"🔔 *Telegram Alarm Started*\n"
            f"Monitoring systemd service: `{s}`\n"
            f"Current status: `{status}`\n"
            f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
        )
        
    return systemd_state

def check_systemd_services(bot_token, chat_id, systemd_state):
    for service, was_active in systemd_state.items(): 
        is_active = systemd_service_is_active(service)
        
        if was_active and not is_active:
            logger.warning(f"Service {service} has stopped!")
            send_telegram_message(
                bot_token, 
                chat_id, 
                f"🚨 *ALERT: Service Down*\n"
                f"The `{service}` service has *stopped*.\n"
                f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
            )
            
        if not was_active and is_active:
            logger.info(f"Service {service} has started!")
            send_telegram_message(
                bot_token, 
                chat_id, 
                f"✅ *Service Recovered*\n"
                f"The `{service}` service is now *running*.\n"
                f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
            )
            
        systemd_state[service] = is_active
        
    return systemd_state

def check_btcpay_health(bot_token, chat_id, btcpay_view_api_key, btcpay_server_url):
    """Check BTCPay Server health endpoint and send alert if health check fails.
    
    Makes a GET request to the BTCPay Server health endpoint and monitors if it's synchronized.
    Sends a Telegram alert if the health check fails or shows not synchronized.
    """
    try:
        if not btcpay_server_url:
            logger.error("BTCPay Server URL not configured in config.json")
            return
        
        # Ensure URL ends with a slash for consistent path joining
        if not btcpay_server_url.endswith('/'):
            btcpay_server_url += '/'
            
        # Make request to health endpoint
        health_url = f"{btcpay_server_url}api/v1/health"
        headers = {}
        
        # Add API key if provided
        if btcpay_view_api_key:
            headers['Authorization'] = f"token {btcpay_view_api_key}"
        
        response = requests.get(health_url, headers=headers, timeout=10)
        
        # Check if response is successful (status code 200)
        if response.status_code != 200:
            error_message = f"🚨 *ALERT: BTCPay Server Health Check Failed*\n"
            error_message += f"Status Code: `{response.status_code}`\n"
            error_message += f"Response: `{response.text[:256]}`\n"  # Truncate large responses
            error_message += f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
            
            logger.error(f"BTCPay health check failed: Status {response.status_code}")
            send_telegram_message(bot_token, chat_id, error_message)
            return
            
        # Try to parse JSON response
        try:
            health_data = response.json()
            
            # Check if the server is synchronized
            if not health_data.get('synchronized', False):
                error_message = f"🚨 *ALERT: BTCPay Server Not Synchronized*\n"
                error_message += f"Health Status: `{json.dumps(health_data, indent=2)}`\n"
                error_message += f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
                
                logger.error(f"BTCPay server not synchronized: {health_data}")
                send_telegram_message(bot_token, chat_id, error_message)
                
        except json.JSONDecodeError:
            # Response is not valid JSON
            error_message = f"🚨 *ALERT: BTCPay Server Health Check Failed*\n"
            error_message += f"Response not valid JSON\n"
            error_message += f"Response: `{response.text[:500]}`\n"  # Truncate large responses
            error_message += f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
            
            logger.error(f"BTCPay health check returned non-JSON response: {response.text}")
            send_telegram_message(bot_token, chat_id, error_message)
                
    except requests.exceptions.RequestException as e:
        # Handle network errors, timeouts, etc.
        error_message = f"🚨 *ALERT: BTCPay Server Health Check Failed*\n"
        error_message += f"Connection Error: `{str(e)}`\n"
        error_message += f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
        
        logger.error(f"Error connecting to BTCPay health endpoint: {e}")
        send_telegram_message(bot_token, chat_id, error_message)
    except Exception as e:
        logger.error(f"Unexpected error checking BTCPay health: {e}")

def check_lnd_payment_rx(bot_token, chat_id):
    try:
        # Calculate timestamp for 90 seconds ago
        ninety_seconds_ago = datetime.now().timestamp() - 90
        since_time = datetime.fromtimestamp(ninety_seconds_ago).strftime('%Y-%m-%d %H:%M:%S')

        # Run journalctl command with --since argument
        result = subprocess.run(
            [
                'journalctl', '-u', 'lnd', '-r',
                '--grep', "Sent 0 satoshis and received [1-9][0-9]* satoshis",
                '--since', since_time
             ],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode != 0 and result.stderr:
            logger.error(f"Error checking LND payments: {result.stderr}")

            output = result.stderr
            send_telegram_message(
                bot_token,
                chat_id,
                f"🚨 *ALERT: LND payment check failed 1*\n"    
                f"```\n{output}\n```\n"
                f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
            )

            return


        output = result.stdout.strip()

        # Process output and send notification if payments were received
        if output != '-- No entries --':
            logger.info(f"LND payment received: {output}")
            send_telegram_message(
                bot_token,
                chat_id,
                f"💰 *LND Payment Received*\n"
                f"```\n{output}\n```\n"
                f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
            )
    except Exception as e:
        logger.error(f"Error checking LND payments: {e}")
        send_telegram_message(
            bot_token,
            chat_id,
            f"🚨 *ALERT: LND payment check failed 2*\n"    
            f"Time: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`"
        )

def main():
    """Main function to monitor service and send alerts."""
    config = load_config()
    bot_token = config.get('telegram_bot_token')
    chat_id = config.get('telegram_chat_id')
    check_interval = config.get('check_interval', 60)  # seconds
    systemd_services = config.get('systemd_services', [])
    enable_mullvad = config.get('enable_mullvad_monitoring', True)
    btcpay_view_api_key = config.get('btcpay_view_api_key', "")
    btcpay_server_url = config.get('btcpay_server_url', "")
    
    if not bot_token or not chat_id:
        logger.error("Telegram bot token or chat ID not configured.")
        exit(1)
    
    # Initialize monitoring states
    mullvad_state = None
    if enable_mullvad:
        logger.info("Initializing Mullvad VPN monitoring")
        mullvad_state = init_mullvad_checks(bot_token, chat_id)
    
    systemd_state = None
    if systemd_services:
        logger.info(f"Initializing systemd service monitoring for: {', '.join(systemd_services)}")
        systemd_state = init_systemd_checks(bot_token, chat_id, systemd_services)
    
    logger.info(f"Monitoring started with check interval of {check_interval} seconds")
    
    while True:
        # Check Mullvad status if enabled
        if mullvad_state is not None:
            mullvad_state = check_mullvad_status(bot_token, chat_id, mullvad_state)

        # Check systemd services if configured
        if systemd_state is not None:
            systemd_state = check_systemd_services(bot_token, chat_id, systemd_state)

        # Check for LND payments
        check_lnd_payment_rx(bot_token, chat_id)
        
        check_btcpay_health(bot_token, chat_id, btcpay_view_api_key, btcpay_server_url)

        # Sleep for the specified interval
        time.sleep(check_interval)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        logger.info("Monitoring stopped by user")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
