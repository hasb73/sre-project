"""
Data Ingest Service
Handles data ingestion workflows and batch processing
"""
import os
import logging
import json
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

@app.route('/health/live', methods=['GET'])
def liveness():
    """Liveness probe - checks if service is running"""
    return jsonify({
        'status': 'alive',
        'service': 'data-ingest',
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
            'service': 'data-ingest',
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

@app.route('/api/v1/ingest', methods=['POST'])
def ingest_data():
    """Ingest data records"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'no data provided'}), 400
        
        # Support both single record and batch
        records = data if isinstance(data, list) else [data]
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        ingested_records = []
        for record in records:
            record_type = record.get('type', 'generic')
            payload = json.dumps(record.get('data', {}))
            source = record.get('source', 'api')
            
            cur.execute(
                """
                INSERT INTO ingested_data (record_type, payload, source, region)
                VALUES (%s, %s, %s, %s)
                RETURNING id, record_type, source, region, created_at
                """,
                (record_type, payload, source, REGION)
            )
            ingested_record = cur.fetchone()
            ingested_records.append(ingested_record)
        
        conn.commit()
        cur.close()
        conn.close()
        
        logger.info(f"Ingested {len(ingested_records)} records in region {REGION}")
        
        return jsonify({
            'ingested': len(ingested_records),
            'records': ingested_records,
            'region': REGION
        }), 201
        
    except Exception as e:
        logger.error(f"Data ingestion error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/ingest/batch', methods=['POST'])
def ingest_batch():
    """Ingest large batch of data"""
    try:
        data = request.get_json()
        records = data.get('records', [])
        
        if not records:
            return jsonify({'error': 'no records provided'}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Batch insert for performance
        values = []
        for record in records:
            record_type = record.get('type', 'generic')
            payload = json.dumps(record.get('data', {}))
            source = record.get('source', 'batch')
            values.append((record_type, payload, source, REGION))
        
        cur.executemany(
            """
            INSERT INTO ingested_data (record_type, payload, source, region)
            VALUES (%s, %s, %s, %s)
            """,
            values
        )
        
        conn.commit()
        count = cur.rowcount
        cur.close()
        conn.close()
        
        logger.info(f"Batch ingested {count} records in region {REGION}")
        
        return jsonify({
            'ingested': count,
            'region': REGION,
            'timestamp': datetime.utcnow().isoformat()
        }), 201
        
    except Exception as e:
        logger.error(f"Batch ingestion error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/ingest/stats', methods=['GET'])
def get_ingest_stats():
    """Get ingestion statistics"""
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # Get overall stats
        cur.execute("""
            SELECT 
                COUNT(*) as total_records,
                COUNT(DISTINCT record_type) as unique_types,
                COUNT(DISTINCT source) as unique_sources
            FROM ingested_data
        """)
        overall_stats = cur.fetchone()
        
        # Get stats by type
        cur.execute("""
            SELECT 
                record_type,
                COUNT(*) as count
            FROM ingested_data
            GROUP BY record_type
            ORDER BY count DESC
            LIMIT 10
        """)
        type_stats = cur.fetchall()
        
        # Get recent ingestion rate (last hour)
        cur.execute("""
            SELECT COUNT(*) as recent_count
            FROM ingested_data
            WHERE created_at > NOW() - INTERVAL '1 hour'
        """)
        recent_stats = cur.fetchone()
        
        cur.close()
        conn.close()
        
        return jsonify({
            'total_records': overall_stats['total_records'],
            'unique_types': overall_stats['unique_types'],
            'unique_sources': overall_stats['unique_sources'],
            'recent_hour_count': recent_stats['recent_count'],
            'by_type': type_stats,
            'region': REGION,
            'timestamp': datetime.utcnow().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Stats error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/ingest/recent', methods=['GET'])
def get_recent_ingestions():
    """Get recent ingested records"""
    try:
        limit = request.args.get('limit', 50, type=int)
        record_type = request.args.get('type')
        
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        if record_type:
            cur.execute(
                """
                SELECT id, record_type, source, region, created_at
                FROM ingested_data
                WHERE record_type = %s
                ORDER BY created_at DESC
                LIMIT %s
                """,
                (record_type, limit)
            )
        else:
            cur.execute(
                """
                SELECT id, record_type, source, region, created_at
                FROM ingested_data
                ORDER BY created_at DESC
                LIMIT %s
                """,
                (limit,)
            )
        
        records = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({
            'records': records,
            'count': len(records),
            'region': REGION
        }), 200
        
    except Exception as e:
        logger.error(f"Recent records error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/info', methods=['GET'])
def get_info():
    """Get service information"""
    return jsonify({
        'service': 'data-ingest',
        'version': '1.0.0',
        'region': REGION,
        'environment': os.getenv('ENVIRONMENT', 'production'),
        'database_host': DB_HOST
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8082, debug=False)
