# ==========================================
# STAGE 1: Build & Package with Maven
# ==========================================
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

WORKDIR /app

# Cache dependency download
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source and package the JAR without running tests
COPY src ./src
RUN mvn clean package -DskipTests

# ==========================================
# STAGE 2: Lightweight Minimal JRE Runtime
# ==========================================
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Create a non-root system user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy ONLY the compiled JAR from Stage 1
COPY --from=builder /app/target/*.jar app.jar

# Give ownership to the non-root user
RUN chown -R appuser:appgroup /app
USER appuser

# Expose Spring Boot port
EXPOSE 8080

# Production JVM flags for container memory awareness
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
