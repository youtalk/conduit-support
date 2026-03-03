#!/bin/bash
# iOS ROS 2 IMU Publisher - Verification Script
# This script verifies the complete data flow

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
echo "  iOS ROS 2 IMU Publisher - Verification"
echo "=========================================="
echo -e "${NC}"

# Check if container is running
echo -e "${BLUE}[1/7] Checking container status...${NC}"
if ! docker ps | grep -q ros_jazzy_zenoh; then
    echo -e "${RED}Error: Container is not running${NC}"
    echo -e "${YELLOW}Run: docker compose up -d${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Container is running${NC}"

# Get container IP
CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ros_jazzy_zenoh)
echo -e "${GREEN}✓ Container IP: ${CONTAINER_IP}${NC}"

# Check if router is running
echo ""
echo -e "${BLUE}[2/7] Checking Zenoh router...${NC}"
if docker exec ros_jazzy_zenoh pgrep -f rmw_zenohd > /dev/null; then
    echo -e "${GREEN}✓ rmw_zenohd is running${NC}"
else
    echo -e "${RED}Error: rmw_zenohd is not running${NC}"
    exit 1
fi

# Test network connectivity
echo ""
echo -e "${BLUE}[3/7] Testing network connectivity...${NC}"
if nc -z -w 5 "$CONTAINER_IP" 7447 2>/dev/null; then
    echo -e "${GREEN}✓ Port 7447 is accessible${NC}"
else
    echo -e "${RED}Error: Cannot connect to port 7447${NC}"
    exit 1
fi

# List ROS 2 topics
echo ""
echo -e "${BLUE}[4/7] Listing ROS 2 topics...${NC}"
TOPICS=$(docker exec ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && source /ros2_ws/install/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic list" 2>/dev/null)

if echo "$TOPICS" | grep -q "/ios/imu"; then
    echo -e "${GREEN}✓ /ios/imu topic exists${NC}"
else
    echo -e "${YELLOW}⚠ /ios/imu topic not found${NC}"
    echo -e "${YELLOW}  Make sure iOS app is running and publishing${NC}"
    echo ""
    echo "Available topics:"
    echo "$TOPICS"
    echo ""
    echo -e "${YELLOW}This is normal if the iOS app hasn't started publishing yet.${NC}"
fi

# Check topic info
echo ""
echo -e "${BLUE}[5/7] Checking /ios/imu topic info...${NC}"
TOPIC_INFO=$(docker exec ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && source /ros2_ws/install/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic info /ios/imu -v" 2>/dev/null || echo "Topic not available")

if echo "$TOPIC_INFO" | grep -q "Type: sensor_msgs/msg/Imu"; then
    echo -e "${GREEN}✓ Topic has correct type (sensor_msgs/msg/Imu)${NC}"

    # Count publishers
    PUB_COUNT=$(echo "$TOPIC_INFO" | grep -c "Publisher count:" || echo "0")
    if [ "$PUB_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ iOS publisher detected${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Topic info not available${NC}"
    echo -e "${YELLOW}  Make sure iOS app is connected and publishing${NC}"
fi

# Sample messages
echo ""
echo -e "${BLUE}[6/7] Sampling messages (5 seconds)...${NC}"
echo -e "${YELLOW}Press Ctrl+C if no messages appear after 5 seconds${NC}"

MSG_SAMPLE=$(timeout 5 docker exec ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && source /ros2_ws/install/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic echo /ios/imu --once" 2>/dev/null || echo "")

if [ -n "$MSG_SAMPLE" ]; then
    echo -e "${GREEN}✓ Messages received!${NC}"
    echo ""
    echo -e "${CYAN}Sample message:${NC}"
    echo "$MSG_SAMPLE" | head -20
    echo ""
else
    echo -e "${YELLOW}⚠ No messages received in 5 seconds${NC}"
    echo -e "${YELLOW}  Make sure iOS app is publishing${NC}"
    echo -e "${YELLOW}  Check Config.plist has correct router IP: tcp/${CONTAINER_IP}:7447${NC}"
fi

# Check message rate
echo ""
echo -e "${BLUE}[7/7] Checking message rate (5 seconds)...${NC}"
RATE_INFO=$(timeout 5 docker exec ros_jazzy_zenoh bash -c "source /opt/ros/jazzy/setup.bash && source /ros2_ws/install/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && ros2 topic hz /ios/imu" 2>/dev/null || echo "")

if [ -n "$RATE_INFO" ]; then
    echo -e "${GREEN}✓ Message rate:${NC}"
    echo "$RATE_INFO"

    # Check if rate is close to 100 Hz
    AVG_RATE=$(echo "$RATE_INFO" | grep "average rate:" | awk '{print $3}' | head -1)
    if [ -n "$AVG_RATE" ]; then
        if (( $(echo "$AVG_RATE > 95.0" | bc -l) )) && (( $(echo "$AVG_RATE < 105.0" | bc -l) )); then
            echo -e "${GREEN}✓ Rate is within expected range (95-105 Hz)${NC}"
        else
            echo -e "${YELLOW}⚠ Rate is outside expected range: ${AVG_RATE} Hz${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ Could not measure rate${NC}"
fi

# Summary
echo ""
echo -e "${CYAN}"
echo "=========================================="
echo "  Verification Summary"
echo "=========================================="
echo -e "${NC}"

# Create summary report
REPORT=""

if docker ps | grep -q ros_jazzy_zenoh; then
    REPORT="${REPORT}${GREEN}✓${NC} Container running\n"
else
    REPORT="${REPORT}${RED}✗${NC} Container not running\n"
fi

if docker exec ros_jazzy_zenoh pgrep -f rmw_zenohd > /dev/null 2>&1; then
    REPORT="${REPORT}${GREEN}✓${NC} Zenoh router active\n"
else
    REPORT="${REPORT}${RED}✗${NC} Zenoh router not active\n"
fi

if nc -z -w 5 "$CONTAINER_IP" 7447 2>/dev/null; then
    REPORT="${REPORT}${GREEN}✓${NC} Network connectivity\n"
else
    REPORT="${REPORT}${RED}✗${NC} Network connectivity\n"
fi

if echo "$TOPICS" | grep -q "/ios/imu"; then
    REPORT="${REPORT}${GREEN}✓${NC} /ios/imu topic exists\n"
else
    REPORT="${REPORT}${YELLOW}⚠${NC} /ios/imu topic not found\n"
fi

if [ -n "$MSG_SAMPLE" ]; then
    REPORT="${REPORT}${GREEN}✓${NC} Messages received\n"
else
    REPORT="${REPORT}${YELLOW}⚠${NC} No messages received\n"
fi

if [ -n "$RATE_INFO" ]; then
    REPORT="${REPORT}${GREEN}✓${NC} Publishing rate detected\n"
else
    REPORT="${REPORT}${YELLOW}⚠${NC} Publishing rate not detected\n"
fi

echo -e "$REPORT"

echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Container IP: ${CYAN}${CONTAINER_IP}${NC}"
echo -e "  Zenoh Port: ${CYAN}7447${NC}"
echo -e "  Expected Config.plist: ${CYAN}tcp/${CONTAINER_IP}:7447${NC}"

echo ""
echo -e "${YELLOW}Next steps:${NC}"
if [ -z "$MSG_SAMPLE" ]; then
    echo ""
    echo "If messages are not appearing:"
    echo "1. Verify iOS app is running in Simulator"
    echo "2. Tap 'Connect & Publish' button in app"
    echo "3. Check Xcode console for errors"
    echo "4. Verify Config.plist settings:"
    echo -e "   ${CYAN}router_locator: tcp/${CONTAINER_IP}:7447${NC}"
    echo -e "   ${CYAN}wire_mode: jazzy${NC}"
    echo -e "   ${CYAN}rate_hz: 100${NC}"
else
    echo ""
    echo -e "${GREEN}Success! Data is flowing correctly.${NC}"
    echo ""
    echo "To monitor continuously:"
    echo -e "  ${CYAN}docker exec -it ros_jazzy_zenoh /usr/local/bin/echo-imu.sh${NC}"
fi

echo ""
