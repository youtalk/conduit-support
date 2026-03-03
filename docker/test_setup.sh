#!/bin/bash
# iOS ROS 2 IMU Publisher - Docker Test Setup Script
# This script sets up the complete testing environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
echo -e "${CYAN}"
echo "=========================================="
echo "  iOS ROS 2 IMU Publisher - Docker Setup"
echo "=========================================="
echo -e "${NC}"

# Check if Docker is installed
echo -e "${BLUE}[1/6] Checking Docker installation...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    echo -e "${YELLOW}Please install Docker Desktop from: https://www.docker.com/products/docker-desktop${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    echo -e "${YELLOW}Please start Docker Desktop from Applications${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker is installed and running${NC}"
docker --version

# Navigate to docker directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Build Docker image
echo ""
echo -e "${BLUE}[2/6] Building Docker image (this may take 10-15 minutes)...${NC}"
docker compose build

# Start container
echo ""
echo -e "${BLUE}[3/6] Starting ROS Jazzy container...${NC}"
docker compose up -d

# Wait for container to be ready
echo ""
echo -e "${BLUE}[4/6] Waiting for container to be ready...${NC}"
sleep 5

# Get container IP
echo ""
echo -e "${BLUE}[5/6] Getting container IP address...${NC}"
CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ros_jazzy_zenoh)

if [ -z "$CONTAINER_IP" ]; then
    echo -e "${RED}Error: Could not get container IP${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Container IP: ${CONTAINER_IP}${NC}"

# Test connectivity
echo ""
echo -e "${BLUE}[6/6] Testing network connectivity...${NC}"
if nc -z -w 5 "$CONTAINER_IP" 7447 2>/dev/null; then
    echo -e "${GREEN}✓ Port 7447 is accessible${NC}"
else
    echo -e "${YELLOW}Warning: Could not verify port 7447 connectivity${NC}"
    echo -e "${YELLOW}This might be normal if rmw_zenohd is still starting${NC}"
fi

# Check container logs
echo ""
echo -e "${BLUE}Checking container logs...${NC}"
echo -e "${CYAN}--- Last 20 lines ---${NC}"
docker compose logs --tail=20

# Summary
echo ""
echo -e "${GREEN}"
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo -e "${NC}"
echo ""
echo -e "${CYAN}Container IP:${NC} ${CONTAINER_IP}"
echo -e "${CYAN}Zenoh Port:${NC} 7447"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Update iOS app configuration:"
echo -e "   ${CYAN}Edit: Config/Config.plist${NC}"
echo -e "   ${CYAN}Set router_locator to: tcp/${CONTAINER_IP}:7447${NC}"
echo -e "   ${CYAN}Set wire_mode to: jazzy${NC}"
echo ""
echo "2. Build and run iOS app in Xcode:"
echo -e "   ${CYAN}Select iPhone 17 Pro (Simulator)${NC}"
echo -e "   ${CYAN}Click Run (⌘R)${NC}"
echo -e "   ${CYAN}Tap 'Connect & Publish' button${NC}"
echo ""
echo "3. Verify data in another terminal:"
echo -e "   ${CYAN}docker exec -it ros_jazzy_zenoh /usr/local/bin/echo-imu.sh${NC}"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo ""
echo "  Check container status:"
echo -e "    ${CYAN}docker compose ps${NC}"
echo ""
echo "  View container logs:"
echo -e "    ${CYAN}docker compose logs -f${NC}"
echo ""
echo "  Echo IMU topic:"
echo -e "    ${CYAN}docker exec -it ros_jazzy_zenoh /usr/local/bin/echo-imu.sh${NC}"
echo ""
echo "  Check topic rate:"
echo -e "    ${CYAN}docker exec -it ros_jazzy_zenoh /usr/local/bin/check-topics.sh${NC}"
echo ""
echo "  Stop container:"
echo -e "    ${CYAN}docker compose down${NC}"
echo ""
