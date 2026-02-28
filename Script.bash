clear
tree .

# Define location info and base directories
COUNTRY="ES"
STATE="Badajoz"
CITY="Badajoz"
ORG="SScertificate"
BASE_DIR="./"  # Current directory

# Function to create a new project and server certificates
create_project() {
  echo "Creating new project..."

  read -p "Enter project name: " PROJECT
  read -p "Enter server hostname (IP or domain): " SERVER_HOST

  PROJECT_DIR="${BASE_DIR}${PROJECT}"
  SERVER_DIR="${PROJECT_DIR}/server"

  mkdir -p "${SERVER_DIR}"
  cd "${PROJECT_DIR}" || exit 1

  # Detect if input is IP address
  if [[ $SERVER_HOST =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    SAN="IP:${SERVER_HOST}"
  else
    SAN="DNS:${SERVER_HOST}"
  fi

  # Store server host for later MQTT testing
  echo "$SERVER_HOST" > server/host.info

  INFO_CA="/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=CA/CN=${PROJECT}-Root-CA"
  INFO_SERVER="/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=Server/CN=${SERVER_HOST}"

  # Generate CA
  openssl req -x509 -nodes -sha256 -newkey rsa:2048 \
    -subj "$INFO_CA" -days 99999 \
    -keyout ca.key -out ca.crt

  # Create SAN config
  cat > server_ext.cnf <<EOF
subjectAltName=${SAN}
EOF

  # Generate Server key + CSR
  openssl req -nodes -sha256 -newkey rsa:2048 \
    -subj "$INFO_SERVER" \
    -keyout server/server.key \
    -out server/server.csr

  # Sign server certificate
  openssl x509 -req -sha256 \
    -in server/server.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server/server.crt \
    -days 99999 \
    -extfile server_ext.cnf

  cp ca.crt server/ca.crt

  rm -f server/server.csr server_ext.cnf *.srl

  echo "Project '${PROJECT}' created."
  echo "Server certificate issued for: ${SERVER_HOST}"
}

# Function to add a new client to an existing project
add_client() {
  echo "Adding new client..."

  # List all projects (directories in BASE_DIR)
  PROJECTS=($(find "$BASE_DIR" -maxdepth 1 -mindepth 1 -type d))
  if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "No projects found."
    exit 1
  fi

  echo "Available projects:"
  select PROJECT in "${PROJECTS[@]##*/}"; do
    if [[ -n "$PROJECT" ]]; then
      PROJECT_DIR="${BASE_DIR}${PROJECT}"
      break
    else
      echo "Invalid choice."
    fi
  done

  # Ask for client name
  read -p "Enter client name: " CLIENT
  read -s -p "Enter password for ${CLIENT}: " CLIENT_PASS
  echo
  read -s -p "Confirm password: " CLIENT_PASS2
  echo

  # Ensure passwords match
  if [[ "$CLIENT_PASS" != "$CLIENT_PASS2" ]]; then
    echo "Passwords do not match."
    exit 1
  fi

  CLIENT_DIR="${PROJECT_DIR}/${CLIENT}"
  PASSWORD_FILE="${PROJECT_DIR}/passwd"

  mkdir -p "$CLIENT_DIR"

  # --- Manage Mosquitto password file ---
  if [[ ! -f "$PASSWORD_FILE" ]]; then
    mosquitto_passwd -c -b -H sha512 "$PASSWORD_FILE" "$CLIENT" "$CLIENT_PASS"
  else
    mosquitto_passwd -b -H sha512 "$PASSWORD_FILE" "$CLIENT" "$CLIENT_PASS"
  fi

  chmod 0700 "$PASSWORD_FILE"

  # --- Generate client certificate signed by the project CA ---
  INFO_CLIENT="/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=Client/CN=${CLIENT}"

  openssl req -new -nodes -sha256 \
    -subj "$INFO_CLIENT" \
    -out "${CLIENT_DIR}/client.csr" \
    -keyout "${CLIENT_DIR}/client.key"

  openssl x509 -req -sha256 \
    -in "${CLIENT_DIR}/client.csr" \
    -CA "${PROJECT_DIR}/ca.crt" \
    -CAkey "${PROJECT_DIR}/ca.key" \
    -CAcreateserial \
    -out "${CLIENT_DIR}/client.crt" \
    -days 99999

  cp "${PROJECT_DIR}/ca.crt" "${CLIENT_DIR}/ca.crt"

  rm -f "${CLIENT_DIR}/client.csr" "${PROJECT_DIR}"/*.srl

  if [[ -f "${PROJECT_DIR}/aclfile" ]]; then
    chmod 0700 "${PROJECT_DIR}/aclfile"
  fi

  echo "Client '${CLIENT}' added to project '${PROJECT}'."
  echo "Certificates saved in: ${CLIENT_DIR}"
  echo "Password entry saved in: ${PASSWORD_FILE}"
}
# Function to test MQTT client (publish or subscribe)
test_mqtt() {
  echo "Testing MQTT..."

  # List all projects (directories in BASE_DIR)
  PROJECTS=($(find "$BASE_DIR" -maxdepth 1 -mindepth 1 -type d))
  if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "No projects found."
    exit 1
  fi

  echo "Available projects:"
  select PROJECT in "${PROJECTS[@]##*/}"; do
    if [[ -n "$PROJECT" ]]; then
      PROJECT_DIR="${BASE_DIR}${PROJECT}"
      break
    else
      echo "Invalid choice."
    fi
  done

  # List all clients inside the selected project (exclude server directory)
  CLIENTS=($(find "$PROJECT_DIR" -maxdepth 1 -mindepth 1 -type d ! -name "server"))
  if [ ${#CLIENTS[@]} -eq 0 ]; then
    echo "No clients found in project '$PROJECT'."
    exit 1
  fi

  echo "Available clients:"
  select CLIENT_DIR in "${CLIENTS[@]}"; do
    if [[ -n "$CLIENT_DIR" ]]; then
      CLIENT=$(basename "$CLIENT_DIR")
      break
    else
      echo "Invalid choice."
    fi
  done

  SERVER_DIR="${PROJECT_DIR}/server"

  if [[ ! -d "$SERVER_DIR" ]]; then
    echo "Server directory '${SERVER_DIR}' does not exist."
    exit 1
  fi

  # Prompt user to enter password
  echo "Enter password for ${CLIENT}:"
  read -s PASSWORD
  echo

  # Choose action
  echo "Choose action:"
  select ACTION in "Publish" "Subscribe"; do
    case $ACTION in
      Publish ) MODE="pub"; break;;
      Subscribe ) MODE="sub"; break;;
      * ) echo "Invalid choice.";;
    esac
  done

  read -p "Enter topic: " TOPIC

  BASE_CMD="mosquitto_${MODE} \
    --cafile ${CLIENT_DIR}/ca.crt \
    --cert ${CLIENT_DIR}/client.crt \
    --key ${CLIENT_DIR}/client.key \
    -h 192.168.0.28 \
    -p 8883 \
    -u ${CLIENT} \
    -P ${PASSWORD} \
    -t ${TOPIC}"

  if [[ "$MODE" == "pub" ]]; then
    echo "Publishing mode. Press Ctrl+C to quit."
    while true; do
      read -p "Enter message: " MESSAGE
      [[ -z "$MESSAGE" ]] && continue
      $BASE_CMD -m "$MESSAGE"
    done
  else
    echo "Subscribing to topic '${TOPIC}'..."
    $BASE_CMD
  fi
}

# Main menu to choose action
echo "Select an action:"
select ACTION in "Create Project" "Add Client" "Test MQTT" "Exit"; do
  case $ACTION in
    "Create Project" ) create_project; break;;
    "Add Client" ) add_client; break;;
    "Test MQTT" ) test_mqtt; break;;
    "Exit" ) exit 0;;
    * ) echo "Invalid choice.";;
  esac
done

