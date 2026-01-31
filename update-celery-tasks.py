#!/usr/bin/env python3
import json
import subprocess
import sys

CLOUDFRONT_URL = "https://d5cdy1ilvnp8r.cloudfront.net"
ALB_URL = "http://giga-mst-alb-1502440895.eu-west-1.elb.amazonaws.com"

def update_task_definition(task_name, current_revision):
    """Update task definition with CloudFront URL"""
    
    # Get current task definition
    result = subprocess.run(
        [
            "aws", "ecs", "describe-task-definition",
            "--task-definition", f"{task_name}:{current_revision}",
            "--query", "taskDefinition"
        ],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Error fetching task definition: {result.stderr}")
        return False
    
    task_def = json.loads(result.stdout)
    
    # Extract only the fields needed for registration
    new_task_def = {
        "family": task_def["family"],
        "taskRoleArn": task_def["taskRoleArn"],
        "executionRoleArn": task_def["executionRoleArn"],
        "networkMode": task_def["networkMode"],
        "requiresCompatibilities": task_def["requiresCompatibilities"],
        "cpu": task_def["cpu"],
        "memory": task_def["memory"],
        "containerDefinitions": []
    }
    
    # Update container definitions
    for container in task_def["containerDefinitions"]:
        new_container = {
            "name": container["name"],
            "image": container["image"],
            "essential": container["essential"],
            "environment": [],
            "secrets": container.get("secrets", []),
            "logConfiguration": container.get("logConfiguration", {}),
        }
        
        # Add command if present
        if "command" in container:
            new_container["command"] = container["command"]
        
        # Add healthCheck if present
        if "healthCheck" in container:
            new_container["healthCheck"] = container["healthCheck"]
        
        # Update environment variables
        for env in container.get("environment", []):
            if env["name"] == "SUPERSET_PUBLIC_URL":
                new_container["environment"].append({
                    "name": "SUPERSET_PUBLIC_URL",
                    "value": CLOUDFRONT_URL
                })
            elif env["name"] == "SESSION_COOKIE_SECURE":
                new_container["environment"].append({
                    "name": "SESSION_COOKIE_SECURE",
                    "value": "true"
                })
            else:
                new_container["environment"].append(env)
        
        # Add new environment variables if not present
        env_names = [e["name"] for e in new_container["environment"]]
        
        if "WEBDRIVER_BASEURL" not in env_names:
            new_container["environment"].append({
                "name": "WEBDRIVER_BASEURL",
                "value": ALB_URL
            })
        
        if "SUPERSET_WEBSERVER_PROTOCOL" not in env_names:
            new_container["environment"].append({
                "name": "SUPERSET_WEBSERVER_PROTOCOL",
                "value": "https"
            })
        
        new_task_def["containerDefinitions"].append(new_container)
    
    # Save to temp file
    temp_file = f"/tmp/{task_name}-new.json"
    with open(temp_file, "w") as f:
        json.dump(new_task_def, f, indent=2)
    
    print(f"Saved new task definition to {temp_file}")
    
    # Register new task definition
    result = subprocess.run(
        [
            "aws", "ecs", "register-task-definition",
            "--cli-input-json", f"file://{temp_file}"
        ],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Error registering task definition: {result.stderr}")
        return False
    
    response = json.loads(result.stdout)
    new_revision = response["taskDefinition"]["revision"]
    print(f"✓ Registered {task_name}:{new_revision}")
    
    return new_revision

# Update Celery Worker
print("Updating giga-mst-celery-worker...")
worker_revision = update_task_definition("giga-mst-celery-worker", 3)

# Update Celery Beat
print("\nUpdating giga-mst-celery-beat...")
beat_revision = update_task_definition("giga-mst-celery-beat", 3)

if worker_revision and beat_revision:
    print("\n✓ All task definitions updated successfully!")
    print(f"  - giga-mst-celery-worker:{worker_revision}")
    print(f"  - giga-mst-celery-beat:{beat_revision}")
else:
    print("\n✗ Some task definitions failed to update")
    sys.exit(1)
