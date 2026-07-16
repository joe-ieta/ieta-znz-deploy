CREATE DATABASE IF NOT EXISTS rag_flow DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS ieta_cdc_core DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'rag_flow'@'%' IDENTIFIED BY 'infini_rag_flow';
CREATE USER IF NOT EXISTS 'ieta_cdc'@'%' IDENTIFIED BY 'infini_rag_flow';
GRANT ALL PRIVILEGES ON rag_flow.* TO 'rag_flow'@'%';
GRANT ALL PRIVILEGES ON ieta_cdc_core.* TO 'ieta_cdc'@'%';
FLUSH PRIVILEGES;
