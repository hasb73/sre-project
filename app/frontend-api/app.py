"""
Frontend API Service
Handles user-facing API requests and coordinates with backend services
"""
import os
import logging
from flask import Flask, jsonify, request
import psycopg2
from psycopg2.extras import RealDictCursor
import requests
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(level=os.getenv('LOG_LEVEL', 'INFO').upper())
logger = logging.getLogger(__name__)

# Configuration from environment variables
DB_HOST = os.getenv('DATABASE_HOST', 'localhost')
DB_PORT = os.getenv('DATABASE_PORT', '5432')
DB_NAME = os.getenv('DATABASE_NAME', 'appdb')
DB_USER = os.getenv('DATABASE_USER', 'appuser')
DB_PASSWORD = os.getenv('DATABASE_PASSWORD', 'password')
REGION = os.getenv('REGION', 'unknown')
BUSINESS_LOGIC_URL = os.getenv('BUSINESS_LOGIC_URL', 'http://business-logic:8081')
DATA_INGEST_URL = os.getenv('DATA_INGEST_URL', 'http://data-ingest:8082')

def get_db_connection():
    """Create database connection"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=5
        )
        return conn
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        raise

@app.route('/health/live', methods=['GET'])
def liveness():
    """Liveness probe - checks if service is running"""
    return jsonify({
        'status': 'alive',
        'service': 'frontend-api',
        'region': REGION,
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/health/ready', methods=['GET'])
def readiness():
    """Readiness probe - checks if service can handle requests"""
    try:
        # Check database connectivity
        conn = get_db_connection()
        conn.close()
        
        # Check backend services
        business_logic_health = requests.get(
            f"{BUSINESS_LOGIC_URL}/health/live",
            timeout=2
        ).status_code == 200
        
        data_ingest_health = requests.get(
            f"{DATA_INGEST_URL}/health/live",
            timeout=2
        ).status_code == 200
        
        if business_logic_health and data_ingest_health:
            return jsonify({
                'status': 'ready',
                'service': 'frontend-api',
                'region': REGION,
                'database': 'connected',
                'backend_services': 'healthy',
                'timestamp': datetime.utcnow().isoformat()
            }), 200
        else:
            return jsonify({
                'status': 'not_ready',
                'reason': 'backend_services_unhealthy'
            }), 503
            
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        return jsonify({
            'status': 'not_ready',
            'reason': str(e)
        }), 503

@app.route('/api/v1/users', methods=['GET'])
def get_users():
    """Get all users"""
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT id, username, email, created_at FROM users ORDER BY created_at DESC LIMIT 100")
        users = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({
            'users': users,
            'count': len(users),
            'region': REGION
        }), 200
    except Exception as e:
        logger.error(f"Error fetching users: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/users', methods=['POST'])
def create_user():
    """Create a new user"""
    try:
        data = request.get_json()
        username = data.get('username')
        email = data.get('email')
        
        if not username or not email:
            return jsonify({'error': 'username and email are required'}), 400
        
        # Call business logic service for validation
        validation_response = requests.post(
            f"{BUSINESS_LOGIC_URL}/api/v1/validate/user",
            json={'username': username, 'email': email},
            timeout=5
        )
        
        if validation_response.status_code != 200:
            return jsonify({'error': 'validation failed'}), 400
        
        # Insert user
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            "INSERT INTO users (username, email) VALUES (%s, %s) RETURNING id, username, email, created_at",
            (username, email)
        )
        user = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        
        logger.info(f"User created: {user['id']} in region {REGION}")
        
        return jsonify({
            'user': user,
            'region': REGION
        }), 201
    except Exception as e:
        logger.error(f"Error creating user: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/data/ingest', methods=['POST'])
def ingest_data():
    """Proxy request to data ingest service"""
    try:
        data = request.get_json()
        
        response = requests.post(
            f"{DATA_INGEST_URL}/api/v1/ingest",
            json=data,
            timeout=10
        )
        
        return jsonify(response.json()), response.status_code
    except Exception as e:
        logger.error(f"Error proxying to data ingest: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/info', methods=['GET'])
def get_info():
    """Get service information"""
    return jsonify({
        'service': 'frontend-api',
        'version': '1.0.0',
        'region': REGION,
        'environment': os.getenv('ENVIRONMENT', 'production'),
        'database_host': DB_HOST,
        'backend_services': {
            'business_logic': BUSINESS_LOGIC_URL,
            'data_ingest': DATA_INGEST_URL
        }
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
