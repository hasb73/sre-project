"""
Business Logic Service
Processes core business operations and validations
"""
import os
import logging
import re
from flask import Flask, jsonify, request
import psycopg2
from psycopg2.extras import RealDictCursor
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

def validate_email(email):
    """Validate email format"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None

def validate_username(username):
    """Validate username format"""
    # Username must be 3-20 characters, alphanumeric and underscores only
    pattern = r'^[a-zA-Z0-9_]{3,20}$'
    return re.match(pattern, username) is not None

@app.route('/health/live', methods=['GET'])
def liveness():
    """Liveness probe - checks if service is running"""
    return jsonify({
        'status': 'alive',
        'service': 'business-logic',
        'region': REGION,
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/health/ready', methods=['GET'])
def readiness():
    """Readiness probe - checks if service can handle requests"""
    try:
        # Check database connectivity
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        
        return jsonify({
            'status': 'ready',
            'service': 'business-logic',
            'region': REGION,
            'database': 'connected',
            'timestamp': datetime.utcnow().isoformat()
        }), 200
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        return jsonify({
            'status': 'not_ready',
            'reason': str(e)
        }), 503

@app.route('/api/v1/validate/user', methods=['POST'])
def validate_user():
    """Validate user data"""
    try:
        data = request.get_json()
        username = data.get('username')
        email = data.get('email')
        
        errors = []
        
        # Validate username
        if not username:
            errors.append('username is required')
        elif not validate_username(username):
            errors.append('username must be 3-20 characters, alphanumeric and underscores only')
        
        # Validate email
        if not email:
            errors.append('email is required')
        elif not validate_email(email):
            errors.append('invalid email format')
        
        # Check if username already exists
        if username and not errors:
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("SELECT id FROM users WHERE username = %s", (username,))
            if cur.fetchone():
                errors.append('username already exists')
            cur.close()
            conn.close()
        
        if errors:
            return jsonify({
                'valid': False,
                'errors': errors,
                'region': REGION
            }), 400
        
        return jsonify({
            'valid': True,
            'region': REGION
        }), 200
        
    except Exception as e:
        logger.error(f"Validation error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/process/order', methods=['POST'])
def process_order():
    """Process business order logic"""
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        amount = data.get('amount')
        
        if not user_id or not amount:
            return jsonify({'error': 'user_id and amount are required'}), 400
        
        # Verify user exists
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT id, username FROM users WHERE id = %s", (user_id,))
        user = cur.fetchone()
        
        if not user:
            cur.close()
            conn.close()
            return jsonify({'error': 'user not found'}), 404
        
        # Insert order
        cur.execute(
            "INSERT INTO orders (user_id, amount, status) VALUES (%s, %s, %s) RETURNING id, user_id, amount, status, created_at",
            (user_id, amount, 'pending')
        )
        order = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        
        logger.info(f"Order processed: {order['id']} for user {user_id} in region {REGION}")
        
        return jsonify({
            'order': order,
            'user': user,
            'region': REGION
        }), 201
        
    except Exception as e:
        logger.error(f"Order processing error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/analytics/summary', methods=['GET'])
def get_analytics_summary():
    """Get analytics summary"""
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Get user count
        cur.execute("SELECT COUNT(*) as user_count FROM users")
        user_count = cur.fetchone()['user_count']
        
        # Get order stats
        cur.execute("""
            SELECT 
                COUNT(*) as order_count,
                COALESCE(SUM(amount), 0) as total_amount,
                COALESCE(AVG(amount), 0) as avg_amount
            FROM orders
        """)
        order_stats = cur.fetchone()
        
        cur.close()
        conn.close()
        
        return jsonify({
            'users': user_count,
            'orders': {
                'count': order_stats['order_count'],
                'total_amount': float(order_stats['total_amount']),
                'average_amount': float(order_stats['avg_amount'])
            },
            'region': REGION,
            'timestamp': datetime.utcnow().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Analytics error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/info', methods=['GET'])
def get_info():
    """Get service information"""
    return jsonify({
        'service': 'business-logic',
        'version': '1.0.0',
        'region': REGION,
        'environment': os.getenv('ENVIRONMENT', 'production'),
        'database_host': DB_HOST
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081, debug=False)
