# ClientLens — System Design Learning Extension

## 1. Purpose

This specification extends the existing ClientLens project.

The primary goal of this extension is to turn ClientLens into a practical **system design learning project**.

The developer should not only implement a working application, but also learn to:

* identify system-design problems
* reason about architectural trade-offs
* estimate system capacity
* choose between synchronous and asynchronous communication
* design for failure
* reason about consistency
* design idempotent distributed workflows
* understand scaling bottlenecks
* design observability
* reason about data ownership
* understand event-driven architectures
* explain architectural decisions in an interview
* recognize when a simple solution is preferable to a distributed one

The project should deliberately contain realistic architectural problems rather than hiding all complexity behind frameworks.

---

# 2. Learning Philosophy

Every significant architectural decision must follow this reasoning pattern:

```text
Requirement
    ↓
Constraint
    ↓
Candidate solutions
    ↓
Decision
    ↓
Trade-off
    ↓
Failure mode
    ↓
Scaling consequence
```

The developer should be encouraged to ask:

> Why do we need this component?

rather than:

> What technology should we use?

The project must avoid introducing distributed systems complexity without a reason.

For example:

Bad:

```text
FastAPI
   ↓
Kafka
   ↓
Redis
   ↓
Worker
   ↓
Another service
```

without a concrete requirement.

Preferred:

```text
LLM processing can take several seconds
        ↓
User does not need the result immediately
        ↓
Synchronous API would unnecessarily couple latency
        ↓
Asynchronous processing is appropriate
        ↓
Kafka + worker
```

---

# 3. System Design Topics to Practice

The implementation should deliberately cover the following topics.

## 3.1 Requirements Analysis

Before implementing major features, document:

### Functional requirements

Examples:

* create client
* upload meeting
* process transcript
* extract insights
* search client history
* synchronize CRM data
* retrieve client context through MCP

### Non-functional requirements

Define explicit targets where appropriate:

* API latency
* throughput
* availability
* data freshness
* processing latency
* consistency requirements
* durability
* scalability
* security

Example:

```text
POST /meetings

Expected:
- p95 API response < 300 ms
- meeting processing may take several seconds/minutes
- API must not wait for LLM processing
- uploaded meeting must not be lost
```

The developer should distinguish:

```text
What must happen immediately?
What can happen later?
What must never be lost?
What can temporarily be stale?
```

---

# 4. Capacity Estimation

Before designing scalable components, perform basic back-of-the-envelope calculations.

Example assumptions:

```text
10,000 tenants
100 clients / tenant
20 meetings / client / year
5 KB metadata / meeting
2 MB transcript / meeting
```

Calculate:

```text
Total meetings
Daily meeting ingestion
Average requests/sec
Peak requests/sec
Database storage
Transcript storage
Kafka event volume
Vector embedding volume
```

The numbers do not need to represent a real Zocks deployment.

The purpose is to practice reasoning from requirements to architecture.

The developer should explicitly identify:

```text
Average load
Peak load
Storage growth
Read/write ratio
Hot paths
Expensive operations
```

---

# 5. Architecture Evolution

The project should be implemented in stages.

## Stage 1 — Simple Architecture

Start with:

```text
React
   ↓
FastAPI
   ↓
MySQL
```

Meeting processing may initially be synchronous.

This establishes the baseline.

---

## Stage 2 — Identify the Bottleneck

Introduce realistic processing time:

```text
Meeting upload
      ↓
Transcript processing
      ↓
LLM analysis
      ↓
Embedding generation
```

Demonstrate why synchronous processing becomes problematic.

Questions to answer:

* What happens if LLM processing takes 20 seconds?
* What happens if 100 meetings arrive simultaneously?
* What happens if the LLM provider is unavailable?
* What happens if the API process crashes during processing?

---

# 6. Asynchronous Processing

Replace synchronous processing with:

```text
React
  ↓
FastAPI
  ↓
MySQL
  ↓
Kafka
  ↓
AI Worker
  ↓
LLM
```

The API should return:

```http
202 Accepted
```

with a processing/job identifier.

Example:

```json
{
  "meetingId": "m123",
  "jobId": "job456",
  "status": "PROCESSING"
}
```

The frontend can query processing status or receive an event.

The developer must document why asynchronous processing is used.

### Required trade-off

```text
Benefit:
- lower API latency
- independent worker scaling
- buffering of traffic spikes
- downstream failure isolation

Cost:
- eventual consistency
- more infrastructure
- harder debugging
- duplicate processing
- additional monitoring
```

---

# 7. Kafka Design

Kafka must not be treated simply as "the queue".

Document:

* topic design
* partition strategy
* partition key
* consumer groups
* ordering requirements
* retention
* retry strategy
* DLQ strategy
* consumer scaling

Example topics:

```text
meeting.created
meeting.transcript.ready
meeting.analysis.requested
meeting.analysis.completed
meeting.indexing.requested
meeting.crm.sync.requested
```

For each topic document:

```text
Producer
Consumer
Partition key
Ordering requirement
Retention
Retry behavior
Failure behavior
```

Example:

```text
meeting.analysis.requested

Key:
meetingId

Consumer:
AI worker

Ordering:
Only events for the same meeting need ordering.

Scaling:
Multiple partitions allow multiple workers.
```

---

# 8. Queue vs Kafka

The developer must explicitly understand the difference between:

```text
Work queue
```

and:

```text
Event streaming platform
```

Practice deciding when each model is appropriate.

Questions:

* Does one worker need to process the task?
* Should multiple independent systems receive the event?
* Do we need replay?
* Do we need event history?
* Do we need ordering?
* Do consumers need independent offsets?

Do not automatically use Kafka everywhere.

---

# 9. Idempotency

Every Kafka consumer must be designed with duplicate delivery in mind.

Assume:

```text
At-least-once delivery
```

rather than relying on perfect exactly-once behavior.

Example:

```text
Kafka
  ↓
AI Worker
  ↓
process(event)
  ↓
DB
```

If the worker crashes after writing the result but before acknowledging the Kafka message:

```text
Kafka
  ↓
same event again
```

The system must safely handle it.

Possible implementation:

```text
processed_events

event_id
consumer_name
processed_at
```

with:

```text
UNIQUE(event_id, consumer_name)
```

or another appropriate idempotency mechanism.

The developer should understand why:

```text
at-least-once + idempotent consumer
```

is often more practical than attempting global exactly-once semantics.

---

# 10. Transactional Outbox

Implement an Outbox pattern.

Instead of:

```text
DB transaction
    ↓
commit

Kafka publish
    ↓
failure
```

use:

```text
┌──────────────────────────┐
│ MySQL transaction        │
│                          │
│ meeting                  │
│ outbox_event             │
└────────────┬─────────────┘
             ↓
       Outbox publisher
             ↓
           Kafka
```

The developer must reproduce the failure scenario:

```text
DB succeeds
Kafka fails
```

and explain how the outbox prevents silent event loss.

The outbox publisher should itself be treated as at-least-once.

Therefore:

```text
Outbox
   ↓
Kafka
```

may produce duplicate events.

Consumers must remain idempotent.

This pattern is particularly important because it connects database transactions, messaging reliability and idempotency in one practical exercise.

---

# 11. Retry Strategy

Implement controlled retries.

Example:

```text
Attempt 1
   ↓
failure
   ↓
1 sec
   ↓
Attempt 2
   ↓
failure
   ↓
5 sec
   ↓
Attempt 3
   ↓
failure
   ↓
DLQ
```

Use exponential backoff with jitter where appropriate.

Document:

* retryable errors
* non-retryable errors
* maximum attempts
* backoff
* DLQ behavior

Do not retry errors indefinitely.

---

# 12. Dead Letter Queue

Introduce a DLQ for messages that repeatedly fail.

Example:

```text
meeting.analysis.requested
              ↓
          AI Worker
          ↙      ↘
      success    failure
                   ↓
                 retry
                   ↓
                 retry
                   ↓
                 DLQ
```

Create an operational workflow:

```text
DLQ
 ↓
inspect
 ↓
identify root cause
 ↓
fix
 ↓
reprocess
```

The developer should understand why DLQs are important in asynchronous architectures.

---

# 13. Backpressure

Create a scenario where:

```text
Incoming meetings:
100/sec

Worker capacity:
20/sec
```

Observe:

```text
Kafka lag ↑
```

Then scale workers:

```text
1 worker
   ↓
5 workers
```

and observe the effect on:

```text
consumer lag
processing latency
CPU
LLM requests
```

The developer should understand that queues absorb bursts but do not magically make the system faster.

---

# 14. Scaling

Identify independent scaling dimensions.

Example:

```text
             ┌── API
             │
Traffic ─────┼── AI workers
             │
             ├── Index workers
             │
             └── CRM workers
```

The API and workers should not necessarily scale together.

Example:

```text
API:
3 replicas

AI Worker:
10 replicas

CRM Worker:
2 replicas
```

Explain why.

Later, demonstrate:

```text
Kafka partitions
        ↓
consumer instances
        ↓
parallel processing
```

---

# 15. Database Design

Use MySQL as the transactional source of truth.

Do not store the entire client history as one giant JSON document.

Practice:

* normalization
* indexes
* foreign keys
* unique constraints
* transaction boundaries
* pagination
* query optimization

Important indexes should be justified.

Example:

```text
(client_id, created_at)
(tenant_id, created_at)
(meeting_id)
(event_id)
(status, created_at)
```

The developer should be able to explain:

```text
Why does this index exist?
Which query uses it?
What happens without it?
What is the write cost?
```

---

# 16. Multi-Tenancy

Every request should resolve:

```text
JWT
 ↓
user
 ↓
tenant
 ↓
authorization
 ↓
database query
```

Never trust:

```text
tenant_id
```

coming from the frontend.

Example:

```sql
SELECT *
FROM meetings
WHERE tenant_id = :authenticatedTenant
AND client_id = :clientId;
```

Practice the security failure:

```text
User from Tenant A
        ↓
requests Client B
        ↓
Client B belongs to Tenant B
        ↓
403 / not found
```

This should be treated as both a security and system-design concern.

---

# 17. Consistency

For every important operation, explicitly classify the consistency requirement.

Example:

| Operation             | Consistency |
| --------------------- | ----------- |
| Create client         | Strong      |
| Save meeting metadata | Strong      |
| LLM analysis          | Eventual    |
| Vector index          | Eventual    |
| CRM synchronization   | Eventual    |
| Processing status     | Eventual    |
| Audit log             | Durable     |

The developer should be able to answer:

> Is it acceptable if this data is 5 seconds old?

If yes, asynchronous processing may be appropriate.

If no, synchronous processing or stronger consistency may be necessary.

---

# 18. SQL vs Vector Search

ClientLens intentionally uses two different retrieval models.

### SQL

Use SQL for:

```text
clientId
meeting date
topics
goals
action items
status
tenant
permissions
```

### Vector search

Use vector search for:

```text
"Find discussions where the client was worried about retirement."
```

The developer should understand that vector search is not a replacement for the relational database.

Use:

```text
structured filtering
        +
semantic retrieval
```

for MCP/RAG queries.

---

# 19. MCP as a System Boundary

The MCP server should NOT directly access MySQL.

Preferred:

```text
Claude / LLM
      ↓
     MCP
      ↓
Application service
      ↓
Repository
      ↓
MySQL / Vector DB
```

This allows:

* authorization
* tenant isolation
* validation
* rate limiting
* auditing
* consistent business rules

The MCP layer should expose high-level capabilities rather than raw database access.

Example:

```text
get_client_context(client_id)
search_client_history(query, client_id)
get_recent_meetings(client_id)
get_open_action_items(client_id)
```

---

# 20. Caching

Introduce caching only after identifying a read bottleneck.

Example:

```text
MCP
 ↓
get_client_context()
 ↓
Redis
 ↓
cache miss
 ↓
MySQL + Vector DB
```

Practice:

* cache-aside
* TTL
* invalidation
* stale data
* cache stampede

The developer should be able to explain:

> Why do we need this cache?

before implementing it.

---

# 21. Failure Mode Analysis

For every major component, document:

```text
What if it is down?
What if it is slow?
What if it returns bad data?
What if it returns twice?
What if the network fails?
What if the process crashes?
What if the database is unavailable?
```

Create a failure matrix:

| Component | Failure     | Expected behavior           |
| --------- | ----------- | --------------------------- |
| MySQL     | unavailable | API fails safely            |
| Kafka     | unavailable | outbox accumulates          |
| LLM       | unavailable | job retries                 |
| Vector DB | unavailable | core DB remains available   |
| CRM       | unavailable | CRM sync remains pending    |
| AI worker | crashes     | Kafka redelivers            |
| MCP       | unavailable | LLM cannot retrieve context |

---

# 22. Observability

Implement:

### Logs

Every distributed operation should have identifiers:

```text
correlation_id
tenant_id
meeting_id
job_id
event_id
```

### Metrics

Track:

```text
HTTP request latency
HTTP error rate
Kafka consumer lag
queue depth
worker throughput
LLM latency
LLM error rate
DB query latency
CRM sync failures
DLQ size
```

### Tracing

Eventually trace:

```text
HTTP request
   ↓
DB
   ↓
Kafka
   ↓
AI worker
   ↓
LLM
   ↓
DB
   ↓
Vector DB
```

The goal is to understand why asynchronous architectures require stronger observability.

---

# 23. Rate Limiting

Introduce rate limits for expensive operations.

Examples:

```text
POST /meetings
POST /meetings/{id}/process
MCP search
LLM operations
```

Reason about:

```text
per user
per tenant
per API key
per endpoint
```

Practice the difference between:

```text
application-level rate limiting
```

and:

```text
infrastructure-level protection
```

---

# 24. API Design

Design APIs before implementation.

Example:

```http
POST /api/meetings
GET /api/meetings/{id}
GET /api/meetings/{id}/status
GET /api/clients/{id}/context
GET /api/clients/{id}/meetings
POST /api/clients/{id}/search
```

For each endpoint document:

```text
request
response
status codes
authentication
authorization
idempotency
pagination
failure cases
```

Practice:

```text
POST /meetings
```

with an idempotency key:

```http
Idempotency-Key: abc123
```

so a client retry does not create two meetings.

---

# 25. Distributed Transactions

Do not use distributed transactions between:

```text
MySQL
Kafka
CRM
LLM
Vector DB
```

Instead practice:

```text
local transaction
+
outbox
+
events
+
idempotent consumers
+
retries
+
eventual consistency
```

For multi-step workflows, consider whether a Saga-like approach is necessary.

Do not introduce Saga unless the project actually benefits from it.

---

# 26. Security

Practice:

* JWT
* RBAC
* tenant isolation
* input validation
* secret management
* API rate limiting
* audit logging
* least privilege
* MCP authorization

Special attention should be given to LLM-related data access.

An LLM should never be able to bypass:

```text
tenant isolation
authorization
data filtering
```

---

# 27. System Design Decision Records

Create an `/docs/adr/` directory.

Every important architecture decision should have an ADR.

Example:

```text
ADR-001-kafka-for-async-processing.md
ADR-002-transactional-outbox.md
ADR-003-idempotent-consumers.md
ADR-004-mysql-as-source-of-truth.md
ADR-005-vector-search.md
ADR-006-mcp-application-boundary.md
ADR-007-cache-strategy.md
```

Each ADR must contain:

```text
# Decision

# Context

# Requirements

# Options

# Decision

# Why

# Trade-offs

# Failure modes

# Consequences

# When we would reconsider this decision
```

This is an important part of the learning objective.

---

# 28. Architecture Evolution Exercises

The project should contain explicit "what if" exercises.

## Exercise A — 10x traffic

Current:

```text
1,000 meetings/day
```

New:

```text
10,000 meetings/day
```

Ask:

* What breaks first?
* Which component scales?
* Which database queries become problematic?
* Does Kafka need more partitions?
* Do workers scale?
* Does the LLM provider become the bottleneck?

---

## Exercise B — 100x traffic

```text
100,000 meetings/day
```

Reconsider:

* database architecture
* partitioning
* caching
* object storage
* vector database
* Kafka partitions
* worker scaling

Do not automatically implement everything.

First explain what the bottleneck would be.

---

## Exercise C — LLM outage

Simulate:

```text
LLM unavailable for 30 minutes
```

Expected reasoning:

```text
API remains available
        ↓
meetings continue entering system
        ↓
events remain durable
        ↓
consumer lag increases
        ↓
LLM recovers
        ↓
workers drain backlog
```

---

## Exercise D — Worker crash

Kill an AI worker during processing.

Verify:

```text
message redelivery
idempotency
no corrupted state
job status
retry count
```

---

## Exercise E — Kafka unavailable

Stop Kafka.

Verify that:

```text
business transaction
+
outbox event
```

remain consistent.

After Kafka returns:

```text
outbox publisher
      ↓
Kafka
```

should recover.

---

## Exercise F — CRM unavailable

Stop the CRM integration.

Expected:

```text
Core application
       ↓
continues working

CRM operation
       ↓
PENDING
       ↓
retry
       ↓
eventual synchronization
```

---

# 29. Kubernetes System Design Exercise

After the application works locally:

```text
React
FastAPI
Kafka
MySQL
AI Worker
Index Worker
CRM Worker
Vector DB
```

deploy to Kubernetes.

Think in terms of independent workloads:

```text
Deployment:
  api

Deployment:
  ai-worker

Deployment:
  index-worker

Deployment:
  crm-worker
```

Then practice:

```text
Horizontal scaling
Health checks
Readiness
Liveness
Resource requests
Resource limits
Rolling deployments
ConfigMaps
Secrets
```

Eventually introduce KEDA for Kafka-based worker autoscaling.

Example concept:

```text
Kafka lag ↑
     ↓
KEDA
     ↓
worker replicas ↑
     ↓
lag ↓
     ↓
worker replicas ↓
```

The important learning objective is not Kubernetes syntax.

It is:

> What metric should cause scaling?

---

# 30. System Design Interview Mode

The project should include a dedicated interview practice mode.

For each major feature, the developer should be able to answer:

### Requirements

```text
What are we building?
Who uses it?
What are the core operations?
```

### Scale

```text
How many users?
How many requests?
What is peak traffic?
How much data?
```

### Architecture

```text
What are the components?
How do they communicate?
```

### Data

```text
Where is the source of truth?
What is cached?
What is eventually consistent?
```

### Reliability

```text
What happens when a dependency fails?
```

### Scaling

```text
What is the bottleneck?
How do we scale it?
```

### Trade-offs

```text
Why this solution?
What did we sacrifice?
```

---

# 31. Mandatory Interview Questions

During implementation, the developer should periodically answer questions such as:

1. Why Kafka instead of synchronous HTTP?
2. Why Kafka instead of RabbitMQ?
3. Why MySQL instead of MongoDB?
4. Why do we need a vector database?
5. Why not store embeddings in MySQL?
6. What happens if Kafka is unavailable?
7. What happens if the worker crashes?
8. Can the same event be processed twice?
9. How do you make the consumer idempotent?
10. Why do we need an outbox?
11. What happens if the outbox publisher crashes?
12. How do you handle retries?
13. What happens to poison messages?
14. What happens if the LLM is down?
15. What happens if the CRM is down?
16. Where is the source of truth?
17. Which data is eventually consistent?
18. Where would you add caching?
19. What would you cache?
20. How would you invalidate it?
21. How would you scale the API?
22. How would you scale AI workers?
23. What determines the number of Kafka partitions?
24. How would you handle 10x traffic?
25. How would you handle 100x traffic?
26. Where is the bottleneck?
27. How would you detect the bottleneck?
28. How would you monitor Kafka lag?
29. How would you debug one request across multiple services?
30. How do you guarantee tenant isolation?
31. Why shouldn't MCP access the DB directly?
32. What happens if vector search is unavailable?
33. What happens if MySQL is unavailable?
34. Which operations require strong consistency?
35. Which operations can be eventually consistent?

---

# 32. Required Architecture Diagrams

Maintain diagrams in:

```text
/docs/architecture/
```

At minimum:

```text
01-current-architecture.png
02-meeting-ingestion.png
03-kafka-flow.png
04-outbox-pattern.png
05-idempotency.png
06-failure-handling.png
07-mcp-rag-flow.png
08-kubernetes-architecture.png
09-scaling.png
```

Also maintain sequence diagrams for important flows.

Example:

```text
React
  │
  │ POST /meetings
  ▼
FastAPI
  │
  ├── MySQL
  │
  └── Outbox
          │
          ▼
      Publisher
          │
          ▼
        Kafka
          │
          ▼
      AI Worker
          │
          ▼
        LLM
          │
          ▼
        MySQL
          │
          ▼
      Vector DB
```

---

# 33. Definition of Done

The project is not considered complete merely because:

```text
Frontend works
Backend works
Kafka works
```

The developer must also be able to explain:

```text
Why each component exists
Why synchronous/asynchronous boundaries exist
Where consistency is required
Where eventual consistency is acceptable
How failures are handled
How duplicate events are handled
How the system scales
What the bottlenecks are
How the system is monitored
What trade-offs were made
```

The final system should therefore have two deliverables:

## Product

A working ClientLens application.

## System Design Portfolio

```text
/docs/
  architecture/
  adr/
  capacity/
  failure-scenarios/
  interview-questions/
```

This documentation is considered part of the project.

---

# 34. Final Learning Goal

By the end of the project, the developer should be able to take an unfamiliar system-design problem and reason through:

```text
Requirements
      ↓
Scale estimation
      ↓
Data model
      ↓
API
      ↓
High-level architecture
      ↓
Sync vs async
      ↓
Consistency
      ↓
Failure modes
      ↓
Idempotency
      ↓
Retries / DLQ
      ↓
Caching
      ↓
Scaling
      ↓
Observability
      ↓
Security
      ↓
Trade-offs
```

The goal is not to memorize:

```text
"Kafka = good"
"Redis = good"
"Kubernetes = scalable"
```

The goal is to develop the reasoning:

```text
Requirement
    ↓
Problem
    ↓
Possible solutions
    ↓
Trade-off
    ↓
Decision
    ↓
Failure mode
    ↓
Scaling strategy
```

That reasoning process is the primary system-design skill this project is intended to develop.
