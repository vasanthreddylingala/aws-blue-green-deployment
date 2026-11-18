CREATE DATABASE IF NOT EXISTS bluegreen_db;
USE bluegreen_db;

CREATE TABLE IF NOT EXISTS tasks (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'PENDING'
);

INSERT INTO tasks (title, description, status) VALUES
('Deploy Infrastructure', 'Provision VPC and ALB via Terraform', 'COMPLETED'),
('Configure EC2 with Ansible', 'Install Docker and runtime dependencies', 'COMPLETED'),
('Blue-Green Deployment', 'Switch ALB traffic from Blue to Green', 'IN_PROGRESS');
