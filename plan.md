AI Client Intelligence Platform — Learning Project

1. Project Overview

Build a production-style educational application inspired by the architectural problems of an AI-powered client intelligence platform such as Zocks.

The goal is not to clone Zocks and not to reproduce its proprietary implementation.

The goal is to learn and demonstrate the technical concepts relevant to a Senior Software Engineer interview for a stack involving:

* Python
* React
* TypeScript
* MySQL
* REST APIs
* AI/LLM integrations
* asynchronous processing
* distributed systems
* Kubernetes
* AWS
* Terraform
* MCP
* authorization and multi-tenancy
* CRM integrations
* observability
* testing and CI/CD

The system should process simulated advisor-client meetings, extract structured client intelligence using an LLM, persist it, synchronize selected information to a simulated CRM, provide semantic retrieval, and expose the client intelligence through an MCP server to an external reasoning model.

The implementation should deliberately favor clean architecture, explicit boundaries, testability, reliability and production-style engineering over building a large number of features.

⸻

2. Learning Objectives

By completing this project, the developer should be able to explain and demonstrate:

1. How a Python backend can be structured for a production SaaS application.
2. How React + TypeScript communicates with a backend.
3. How meeting data can be transformed into structured intelligence using an LLM.
4. How asynchronous event-driven processing works.
5. Why Kafka/message queues are useful for long-running AI workflows.
6. How to design idempotent consumers.
7. How to separate transactional data from semantic/vector search.
8. How RAG works.
9. How MCP differs from RAG and REST APIs.
10. How an MCP server can expose domain-specific data to an AI reasoning model.
11. How OAuth/JWT-based authorization protects tenant data.
12. How CRM integrations should handle retries and failures.
13. How to design a multi-tenant SaaS backend.
14. How to containerize the application.
15. How the system could be deployed to Kubernetes.
16. How Terraform could provision the infrastructure.
17. How AWS services could map to the architecture.
18. How to test synchronous and asynchronous workflows.
19. How to monitor and debug a distributed application.
20. How to discuss architectural tradeoffs in a senior system-design interview.

⸻

3. Product Concept

The application is called:

ClientLens

ClientLens is an AI-powered client intelligence platform for financial advisors.

An advisor can:

* create clients
* create households
* upload or enter meeting transcripts
* process meetings
* view summaries
* view extracted topics
* view goals
* view concerns
* view action items
* search historical client conversations
* synchronize action items with a simulated CRM
* ask an external AI assistant questions about clients through MCP

Example:

An advisor enters a meeting transcript:

The client is considering selling their business within the next two or three years. They are concerned about taxes and want to transfer part of the business to their son.

The system should extract:

{
  "topics": [
    "business succession",
    "business sale",
    "tax planning"
  ],
  "goals": [
    {
      "description": "Transfer business to son",
      "timeframe": "2-3 years"
    }
  ],
  "concerns": [
    "tax implications"
  ],
  "action_items": [
    {
      "description": "Discuss succession planning options",
      "owner": "advisor"
    }
  ]
}

Later the advisor can ask through MCP:

What unresolved planning topics have we discussed with John over the last year?

The MCP layer should retrieve the relevant ClientLens data and expose it to the reasoning model.

⸻

4. Architecture

Use the following logical architecture:

                         ┌───────────────────────┐
                         │      React + TS       │
                         │       Frontend        │
                         └───────────┬───────────┘
                                     │
                                     │ HTTPS / REST
                                     ▼
                         ┌───────────────────────┐
                         │      API Gateway      │
                         │       FastAPI         │
                         └───────────┬───────────┘
                                     │
             ┌───────────────────────┼────────────────────────┐
             │                       │                        │
             ▼                       ▼                        ▼
       Client Service         Meeting Service          Search Service
             │                       │                        │
             │                       ▼                        │
             │                  Event Bus                     │
             │                   Kafka                        │
             │                       │                        │
             │             ┌─────────┴──────────┐             │
             │             ▼                    ▼             │
             │      AI Analysis Worker     CRM Sync Worker     │
             │             │                    │             │
             │             ▼                    ▼             │
             │         LLM Provider        Mock CRM API        │
             │             │
             │             ▼
             │       Structured Intelligence
             │             │
             └─────────────┼─────────────────────────────┐
                           ▼                             ▼
                     MySQL Database                Vector Store
                           │                             │
                           └──────────────┬──────────────┘
                                          │
                                          ▼
                                   Retrieval Service
                                          │
                                          ▼
                                    MCP Server
                                          │
                              ┌───────────┴───────────┐
                              ▼                       ▼
                           Claude                  ChatGPT

⸻

5. Technology Stack

Backend

Use:

* Python 3.12+
* FastAPI
* Pydantic
* SQLAlchemy
* Alembic
* MySQL 8
* pytest
* httpx
* asyncio

Recommended project structure:

backend/
├── app/
│   ├── api/
│   ├── core/
│   ├── domain/
│   ├── services/
│   ├── repositories/
│   ├── models/
│   ├── schemas/
│   ├── workers/
│   ├── integrations/
│   ├── mcp/
│   └── main.py
├── tests/
├── alembic/
├── pyproject.toml
└── Dockerfile

Do not create a single monolithic main.py.

Use clear separation between:

* API layer
* domain/business logic
* persistence
* external integrations
* asynchronous workers

⸻

6. Frontend

Use:

* React
* TypeScript
* Vite
* React Router
* TanStack Query
* a lightweight component library or clean CSS

Do not use Redux unless there is a real state-management reason.

Frontend structure:

frontend/
├── src/
│   ├── api/
│   ├── components/
│   ├── features/
│   │   ├── clients/
│   │   ├── meetings/
│   │   ├── intelligence/
│   │   └── crm/
│   ├── pages/
│   ├── hooks/
│   ├── types/
│   ├── auth/
│   └── main.tsx
├── package.json
└── Dockerfile

⸻

7. Database

Use MySQL as the primary transactional database.

Entities:

Tenant
User
Client
Household
Meeting
MeetingParticipant
MeetingTranscript
MeetingTopic
ClientGoal
ClientConcern
LifeEvent
ActionItem
ClientInsight
CRMConnection
CRMOperation
ProcessingJob
AuditLog

Important relationships:

Tenant
 ├── Users
 ├── Clients
 │     ├── Meetings
 │     │     ├── Transcript
 │     │     ├── Topics
 │     │     └── Participants
 │     ├── Goals
 │     ├── Concerns
 │     ├── Life Events
 │     └── Insights
 │
 └── CRM Connections

Every tenant-owned entity must contain or be traceable to:

tenant_id

The backend must never rely on the frontend to enforce tenant isolation.

⸻

8. Multi-Tenancy

Implement tenant isolation from the beginning.

Example:

Tenant A
 ├── User A1
 ├── Client A
 └── Client B
Tenant B
 ├── User B1
 └── Client C

User A must never be able to retrieve Client C.

Authorization must be enforced server-side.

Every request should resolve:

authenticated user
        ↓
tenant
        ↓
permissions
        ↓
resource

Never trust:

GET /clients/{client_id}

without verifying that the client belongs to the authenticated user’s tenant.

⸻

9. Authentication

Implement JWT-based authentication.

Required roles:

ADMIN
ADVISOR
READ_ONLY

Permissions:

clients:read
clients:write
meetings:read
meetings:write
intelligence:read
crm:write
mcp:read
admin:manage

Use short-lived access tokens.

Keep authentication implementation simple but production-oriented.

Do not implement social login initially.

⸻

10. Meeting Ingestion

The frontend must allow an advisor to create a meeting.

Initial version:

POST /api/v1/meetings

Request:

{
  "client_id": "uuid",
  "title": "Annual Review",
  "occurred_at": "2026-09-22T10:00:00Z",
  "transcript": "..."
}

Do not implement real-time audio capture initially.

The educational objective is the backend processing pipeline rather than audio engineering.

Later, an optional audio ingestion feature can be added.

⸻

11. Meeting Processing Pipeline

Meeting processing must be asynchronous.

Initial flow:

POST /meetings
       │
       ▼
Create meeting
       │
       ▼
Publish MeetingCreated
       │
       ▼
Kafka
       │
       ▼
AI Analysis Worker
       │
       ▼
LLM
       │
       ▼
Structured intelligence
       │
       ▼
Persist
       │
       ▼
Publish IntelligenceExtracted

Meeting status:

CREATED
PROCESSING
COMPLETED
FAILED

The API should return quickly rather than waiting for the LLM.

Example:

POST /api/v1/meetings

Response:

{
  "meeting_id": "...",
  "status": "PROCESSING"
}

⸻

12. Kafka

Use Kafka for asynchronous processing.

Topics:

meeting.created
meeting.processing
meeting.completed
meeting.failed
intelligence.extracted
crm.sync.requested
crm.sync.completed
crm.sync.failed

Each event must contain:

{
  "event_id": "uuid",
  "event_type": "MeetingCreated",
  "occurred_at": "...",
  "tenant_id": "uuid",
  "aggregate_id": "meeting-id",
  "payload": {}
}

Important:

* consumers must be idempotent
* events must have unique IDs
* failed events must be retryable
* processing failures must be observable
* avoid distributed transactions where possible

⸻

13. Idempotency

Every asynchronous consumer must support idempotency.

Implement:

processed_events

table:

event_id
consumer_name
processed_at

Before processing:

if event already processed:
    skip

This is mandatory for:

* AI worker
* CRM worker
* indexing worker

Demonstrate why this matters.

Example failure:

Consumer
   ↓
CRM API
   ↓
success
   ↓
network timeout
   ↓
consumer thinks request failed
   ↓
retry

Without idempotency:

duplicate CRM record

With idempotency:

same event → same logical operation

⸻

14. AI Analysis

Create an abstraction:

class LLMProvider(Protocol):
    async def analyze_meeting(
        self,
        transcript: str,
        context: ClientContext
    ) -> MeetingAnalysis:
        ...

Implement:

MockLLMProvider

and one real provider:

OpenAIProvider

or:

AnthropicProvider

The provider must be configurable.

Do not couple the business logic directly to a specific LLM SDK.

⸻

15. Structured LLM Output

The LLM must return validated structured output.

Use Pydantic:

class MeetingAnalysis(BaseModel):
    summary: str
    topics: list[Topic]
    goals: list[Goal]
    concerns: list[Concern]
    action_items: list[ActionItem]
    life_events: list[LifeEvent]

The LLM response must pass schema validation.

Invalid output:

LLM
 ↓
Pydantic validation
 ↓
FAILED

Do not persist invalid AI output as trusted structured data.

⸻

16. AI Reliability

The system must explicitly treat LLM output as probabilistic.

Implement:

AI output
    ↓
schema validation
    ↓
business validation
    ↓
persistence

Store:

model
model_version
prompt_version
processing_timestamp
confidence if available

Do not claim that the LLM is always correct.

⸻

17. Client Intelligence

Client intelligence should be represented separately from individual meetings.

Example:

Meeting
   ↓
Observation
   ↓
Client Intelligence

Example:

Meeting 1:

Client mentioned possible business sale.

Meeting 2:

Client said succession is becoming important.

Meeting 3:

Client expects transition within 2-3 years.

The system should allow the client profile to expose:

Goals
Concerns
Life Events
Recurring Topics
Open Action Items
Historical Insights

Do not overwrite historical facts blindly.

Maintain provenance:

insight
   ↓
source meeting(s)

⸻

18. Semantic Search

Implement semantic search over meeting content.

The search architecture:

Meeting transcript
       ↓
Chunking
       ↓
Embedding
       ↓
Vector store

For the educational project, use:

PostgreSQL + pgvector

if practical.

If using MySQL as the primary DB, the vector store may be a separate service.

The design must explicitly explain why:

MySQL

is used for transactional data while:

Vector DB

is used for semantic retrieval.

⸻

19. Retrieval Service

Create:

RetrievalService

Responsibilities:

* retrieve client history
* retrieve relevant meetings
* retrieve relevant transcript chunks
* retrieve goals
* retrieve concerns
* retrieve action items
* combine structured and semantic results

Example:

retrieve_client_context(
    client_id,
    query,
    user_context
)

Output:

{
  "client": {},
  "recent_meetings": [],
  "relevant_meetings": [],
  "goals": [],
  "concerns": [],
  "open_actions": []
}

The retrieval layer must enforce authorization.

⸻

20. RAG

Implement a basic RAG pipeline:

Question
   ↓
Embedding
   ↓
Vector search
   ↓
Top K chunks
   ↓
Structured client data
   ↓
Context assembly
   ↓
LLM
   ↓
Answer

Example question:

What has John said about selling his business?

The retriever should find relevant historical meetings rather than sending every transcript to the LLM.

Implement configurable:

top_k
similarity_threshold
max_context_tokens

⸻

21. MCP Server

Implement an MCP server for ClientLens.

The MCP server should expose read-only tools.

Initial tools:

get_client
get_client_summary
get_recent_meetings
search_client_history
get_open_action_items
get_client_goals
get_client_concerns

Example:

search_client_history

Input:

{
  "client_id": "uuid",
  "query": "business succession",
  "limit": 10
}

The MCP server must:

1. authenticate the user
2. determine tenant
3. validate permissions
4. retrieve relevant data
5. return structured data
6. record an audit event

⸻

22. MCP Security

MCP access must be read-only.

The MCP server must not initially expose:

create_client
update_client
delete_client
create_crm_task
delete_crm_task

This is intentional.

The purpose is to learn how to securely expose contextual data to an external reasoning model before allowing AI-driven actions.

Every MCP request must create an audit entry:

user_id
tenant_id
tool_name
timestamp
resource identifiers

Do not store full sensitive prompts or model outputs unless explicitly required.

⸻

23. MCP vs RAG

Document this distinction in the project README.

MCP:

AI application
      ↓
MCP
      ↓
ClientLens

RAG:

Question
   ↓
retrieval
   ↓
relevant data
   ↓
LLM

ClientLens combines both:

Claude
  ↓
MCP
  ↓
ClientLens MCP Server
  ↓
Retrieval Service
  ↓
MySQL + Vector Store
  ↓
Relevant context
  ↓
Claude reasoning

⸻

24. CRM Integration

Implement a simulated CRM.

Create:

MockCRM

API:

POST /crm/contacts
POST /crm/tasks
PATCH /crm/contacts/{id}
GET /crm/contacts/{id}

The ClientLens CRM integration must synchronize:

* client contact information
* meeting summary
* action items

The CRM integration must be asynchronous.

Flow:

IntelligenceExtracted
        ↓
CRM Sync Requested
        ↓
Kafka
        ↓
CRM Worker
        ↓
Mock CRM

⸻

25. CRM Reliability

Implement:

* retry
* exponential backoff
* idempotency
* timeout
* circuit breaker or equivalent protection
* dead-letter handling

Simulate CRM failures.

Example configuration:

CRM_FAILURE_RATE=0.1

The system should survive temporary CRM outages.

⸻

26. REST API

Use versioned APIs:

/api/v1/auth
/api/v1/clients
/api/v1/households
/api/v1/meetings
/api/v1/intelligence
/api/v1/search
/api/v1/crm

Examples:

GET    /api/v1/clients
POST   /api/v1/clients
GET    /api/v1/clients/{id}
POST   /api/v1/meetings
GET    /api/v1/meetings/{id}
GET    /api/v1/clients/{id}/intelligence
GET    /api/v1/clients/{id}/actions
POST   /api/v1/search

Use OpenAPI documentation generated by FastAPI.

⸻

27. Frontend Features

Build the following pages.

Dashboard

Show:

Total clients
Meetings this week
Open action items
Failed processing jobs
CRM synchronization status

Clients

List:

Name
Household
Last meeting
Open actions
Important topics

Client Details

Show:

Client profile
Goals
Concerns
Life events
Open actions
Recent meetings
Historical intelligence

Meeting Details

Show:

Meeting metadata
Transcript
Summary
Topics
Goals
Concerns
Action items
Processing status
AI metadata

Search

Allow:

Search client history

Example:

"business succession"

Display:

Relevant client
Relevant meeting
Matching transcript excerpt
Date
Similarity score

Processing Monitor

Show asynchronous jobs:

Meeting
Status
Started
Completed
Retries
Error

This page exists specifically to make the distributed processing architecture visible.

⸻

28. Frontend Architecture

Use React Query/TanStack Query for server state.

Do not duplicate server state in a global store unnecessarily.

Example:

useClients()
useClient()
useMeetings()
useMeeting()
useClientIntelligence()
useSearch()

Use TypeScript interfaces generated from OpenAPI if practical.

The frontend should not contain business authorization logic.

⸻

29. Real-Time Processing Updates

Implement Server-Sent Events or WebSocket updates for processing status.

Example:

Meeting uploaded
       ↓
PROCESSING
       ↓
AI ANALYSIS
       ↓
INDEXING
       ↓
CRM SYNC
       ↓
COMPLETED

Frontend should update without manual refresh.

This is intentionally useful for learning real-time systems.

⸻

30. Observability

Implement structured JSON logging.

Every request should include:

request_id
trace_id if available
tenant_id
user_id
service
operation
duration
status

Every asynchronous event should include:

event_id
correlation_id
tenant_id

Example:

meeting_id=m-123
event_id=e-456
correlation_id=c-789

The same correlation ID should be visible across:

API
Kafka
AI worker
CRM worker
MCP

⸻

31. Metrics

Expose metrics for:

HTTP request count
HTTP latency
HTTP errors
Kafka consumer lag
AI processing latency
AI failures
CRM sync failures
CRM retry count
MCP requests
MCP latency
database query latency

Use Prometheus-compatible metrics.

Optional:

Grafana

⸻

32. Distributed Tracing

If feasible, implement OpenTelemetry.

Trace:

HTTP request
   ↓
Kafka publish
   ↓
AI worker
   ↓
LLM call
   ↓
database
   ↓
CRM

The purpose is to demonstrate how to debug distributed workflows.

⸻

33. Error Handling

Define consistent API errors.

Example:

{
  "error": {
    "code": "CLIENT_NOT_FOUND",
    "message": "Client does not exist"
  },
  "request_id": "..."
}

Do not expose internal stack traces.

LLM failures should result in:

PROCESSING_FAILED

and not a partially persisted trusted result.

⸻

34. Security

Implement:

* JWT authentication
* RBAC
* tenant isolation
* input validation
* SQL parameterization through ORM
* secret management through environment variables
* no credentials in source control
* audit logging
* MCP permission checks
* rate limiting on public APIs
* request size limits

Do not log:

* access tokens
* passwords
* full transcripts
* sensitive client data

unless explicitly required for debugging in local development.

⸻

35. Data Privacy

Treat all client data as sensitive.

The application should support:

delete client
delete meeting

with appropriate cascading behavior.

Document:

* data retention
* deletion behavior
* audit log retention
* LLM provider data handling assumptions

Do not send real personal or financial data to the application.

Use synthetic demo data only.

⸻

36. Docker

Provide:

docker-compose.yml

with:

frontend
backend
mysql
kafka
zookeeper or Kafka-compatible setup
vector database if needed
mock-crm

Keep local development simple.

One command should start the core system:

docker compose up

⸻

37. Kubernetes

Create Helm charts.

Namespaces:

clientlens

Deployments:

backend
ai-worker
crm-worker
index-worker
mcp-server
frontend

Infrastructure dependencies may initially run outside Kubernetes.

Provide:

helm/
  clientlens/
    Chart.yaml
    values.yaml
    templates/

Include:

* ConfigMaps
* Secrets
* Deployments
* Services
* Ingress
* HorizontalPodAutoscaler

⸻

38. Kubernetes Scaling

The AI worker must be independently scalable.

Example:

backend replicas: 2
ai-worker replicas: 3
crm-worker replicas: 2

Explain why:

API traffic

and:

AI processing load

are different scaling dimensions.

If Kafka lag increases:

increase AI worker replicas

rather than scaling the entire backend.

⸻

39. Terraform

Create an educational AWS Terraform configuration.

Do not require deployment to AWS initially.

Terraform should model:

VPC
EKS
RDS/MySQL
S3
IAM
security groups

Structure:

terraform/
├── modules/
│   ├── network/
│   ├── database/
│   ├── kubernetes/
│   └── storage/
└── environments/
    └── dev/

Do not over-engineer the infrastructure.

The goal is to understand:

Terraform → infrastructure
Helm → Kubernetes applications

⸻

40. AWS Architecture

Document a possible AWS production architecture:

Route53
   │
   ▼
ALB
   │
   ▼
EKS
   │
   ├── API
   ├── AI workers
   ├── CRM workers
   └── MCP server
        │
        ├── RDS MySQL
        ├── S3
        ├── Kafka
        └── Vector Search

The project does not need to deploy all of this during the first phase.

⸻

41. Testing Strategy

Implement multiple testing levels.

Unit tests

Test:

* domain services
* validation
* authorization
* event handlers
* retrieval logic
* CRM idempotency

API tests

Test:

authentication
authorization
tenant isolation
CRUD
error handling

Integration tests

Use real MySQL through Testcontainers if practical.

Test:

API → DB
Worker → DB
Worker → Kafka
CRM → Worker

AI tests

Do not rely exclusively on live LLM calls.

Use deterministic fixtures:

transcript fixture
      ↓
mock LLM response
      ↓
expected structured intelligence

Optional evaluation tests can use real LLMs.

⸻

42. CI/CD

Create GitHub Actions workflow:

Pull Request
    ↓
lint
    ↓
type check
    ↓
unit tests
    ↓
integration tests
    ↓
build Docker images

Main branch:

merge
 ↓
build
 ↓
test
 ↓
Docker image
 ↓
push registry

Deployment can initially remain manual.

Later:

GitHub Actions
      ↓
Helm
      ↓
Kubernetes

⸻

43. Development Phases

The project must be implemented incrementally.

Phase 1 — Foundation

Build:

* repository
* Docker Compose
* FastAPI
* React
* MySQL
* authentication
* clients
* meetings

Goal:

React → FastAPI → MySQL

⸻

Phase 2 — AI Processing

Implement:

* meeting processing
* LLM abstraction
* mock LLM
* structured extraction
* Pydantic validation
* processing statuses

Goal:

Meeting → AI → structured intelligence

⸻

Phase 3 — Kafka

Introduce:

* Kafka
* events
* AI worker
* idempotency
* retries

Goal:

API → Kafka → Worker → DB

⸻

Phase 4 — Search/RAG

Implement:

* chunking
* embeddings
* vector search
* retrieval service
* RAG

Goal:

Question → Retrieval → Context → LLM

⸻

Phase 5 — CRM

Implement:

* mock CRM
* CRM worker
* retries
* idempotency
* dead-letter handling

Goal:

ClientLens → asynchronous CRM synchronization

⸻

Phase 6 — MCP

Implement:

* MCP server
* read-only tools
* authentication
* authorization
* audit logging

Goal:

Claude/ChatGPT
      ↓
MCP
      ↓
ClientLens
      ↓
retrieval

⸻

Phase 7 — Production Engineering

Add:

* structured logging
* metrics
* OpenTelemetry
* health checks
* readiness/liveness probes
* rate limiting
* tracing
* error handling

⸻

Phase 8 — Kubernetes

Add:

* Helm
* Deployments
* Services
* Ingress
* HPA
* ConfigMaps
* Secrets

⸻

Phase 9 — Terraform/AWS

Add:

* Terraform
* VPC
* EKS
* RDS
* S3
* IAM

Do not make AWS deployment a prerequisite for completing the application.

⸻

44. Important Architectural Constraints

The implementation must follow these rules.

Rule 1

Do not build everything as one service.

The system should demonstrate service boundaries.

Rule 2

Do not make everything asynchronous.

Use synchronous REST where it makes sense.

Use asynchronous processing for:

* AI processing
* indexing
* CRM synchronization

Rule 3

Do not call an LLM directly from every API endpoint.

Centralize AI access behind an abstraction.

Rule 4

Do not trust LLM output.

Validate it.

Rule 5

Do not trust client-provided tenant IDs.

Resolve tenant identity from authentication.

Rule 6

Do not allow MCP to bypass authorization.

MCP must use the same authorization model as the application.

Rule 7

Do not put sensitive data into logs.

Rule 8

Every event consumer must be idempotent.

Rule 9

Historical client information should have provenance.

Rule 10

Do not over-engineer infrastructure before the application works locally.

⸻

45. What Should NOT Be Implemented Initially

Do not implement:

* real phone/video integrations
* real Salesforce integration
* real financial portfolio integrations
* real financial calculations
* production-grade audio recording
* complex frontend design system
* multi-region AWS
* service mesh
* Kubernetes operator development
* complex agent framework
* autonomous AI actions
* MCP write tools

These distract from the learning objectives.

⸻

46. AI Provider Abstraction

The application should support:

MOCK
OPENAI
ANTHROPIC

through configuration:

LLM_PROVIDER=mock

The rest of the application should not care which provider is being used.

Architecture:

AIAnalysisService
       │
       ▼
LLMProvider interface
       │
 ┌─────┼─────────┐
 ▼     ▼         ▼
Mock OpenAI   Anthropic

⸻

47. MCP Tool Design

MCP tools should return concise, structured information.

Example:

get_client_summary

should not return five years of raw transcripts.

Instead:

{
  "client": {
    "id": "...",
    "name": "John Smith"
  },
  "goals": [],
  "concerns": [],
  "open_actions": [],
  "recent_meetings": []
}

For historical questions:

search_client_history

should perform retrieval.

This demonstrates the principle:

MCP = interface
Retrieval = implementation
LLM = reasoning

⸻

48. Example End-to-End Scenario

Implement a demo scenario:

Initial client

John Smith

Meeting 1

Transcript mentions:

retirement
business sale
tax planning

Meeting 2

Transcript mentions:

business succession
son taking over company

Meeting 3

Transcript mentions:

business sale may happen sooner than expected

The system should produce:

Client goals
- succession planning
Concerns
- tax implications
Recurring topics
- business sale
- succession
Open actions
- schedule tax planning discussion

Then query:

What unresolved planning topics have been discussed with John?

The MCP/RAG system should return relevant evidence from the three meetings.

⸻

49. Senior Interview Exercises

After the core project works, create design exercises.

Exercise 1

The AI worker becomes overloaded.

Question:

How would you scale it independently?

Expected topics:

* Kafka partitions
* consumer groups
* horizontal scaling
* backpressure
* rate limits

⸻

Exercise 2

CRM API is unavailable for 20 minutes.

Question:

How do you prevent data loss?

Expected:

* Kafka persistence
* retries
* DLQ
* idempotency
* exponential backoff

⸻

Exercise 3

Advisor A can see Advisor B’s clients.

Question:

Where could the authorization bug be?

Expected investigation:

JWT
 ↓
tenant resolution
 ↓
repository filtering
 ↓
service authorization
 ↓
MCP authorization

⸻

Exercise 4

Claude requests:

“Tell me everything about client John.”

Question:

How do you prevent excessive data exposure?

Expected:

* authorization
* data minimization
* retrieval
* context limits
* audit logging

⸻

Exercise 5

LLM generates incorrect client information.

Question:

How do you reduce the impact?

Expected:

* source attribution
* structured extraction
* validation
* confidence
* human review
* grounding
* provenance

⸻

Exercise 6

Search becomes slow with 100 million transcript chunks.

Question:

How do you scale retrieval?

Expected:

* indexing
* vector index configuration
* partitioning
* metadata filtering
* top-K retrieval
* caching
* separate search infrastructure

⸻

50. Definition of Done

The project is considered complete when:

* [ ]	React frontend runs locally
* [ ]	Python backend runs locally
* [ ]	MySQL runs through Docker
* [ ]	users can authenticate
* [ ]	tenants are isolated
* [ ]	clients can be created
* [ ]	meetings can be created
* [ ]	meetings are processed asynchronously
* [ ]	Kafka is used for processing events
* [ ]	AI analysis produces structured output
* [ ]	LLM output is validated
* [ ]	client intelligence is persisted
* [ ]	historical semantic search works
* [ ]	basic RAG works
* [ ]	mock CRM integration works
* [ ]	CRM failures are retried
* [ ]	consumers are idempotent
* [ ]	MCP server exposes read-only tools
* [ ]	MCP respects authorization
* [ ]	MCP requests are audited
* [ ]	frontend displays processing status
* [ ]	logs are structured
* [ ]	metrics exist
* [ ]	unit tests exist
* [ ]	integration tests exist
* [ ]	Docker Compose starts the application
* [ ]	Helm deployment exists
* [ ]	Terraform architecture exists
* [ ]	CI pipeline runs tests and builds images
* [ ]	README explains architecture and tradeoffs

⸻

51. Expected Repository Structure

Final repository:

clientlens/
│
├── backend/
│   ├── app/
│   │   ├── api/
│   │   ├── core/
│   │   ├── domain/
│   │   ├── models/
│   │   ├── repositories/
│   │   ├── schemas/
│   │   ├── services/
│   │   ├── workers/
│   │   ├── integrations/
│   │   ├── mcp/
│   │   └── main.py
│   ├── tests/
│   ├── alembic/
│   ├── Dockerfile
│   └── pyproject.toml
│
├── frontend/
│   ├── src/
│   │   ├── api/
│   │   ├── components/
│   │   ├── features/
│   │   ├── pages/
│   │   ├── hooks/
│   │   └── types/
│   ├── Dockerfile
│   └── package.json
│
├── infrastructure/
│   ├── docker/
│   ├── helm/
│   └── terraform/
│
├── docs/
│   ├── architecture.md
│   ├── decisions/
│   ├── mcp.md
│   ├── rag.md
│   └── interview-exercises.md
│
├── .github/
│   └── workflows/
│
├── docker-compose.yml
├── README.md
└── .env.example

⸻

52. Kiro Implementation Instructions

Implement the project incrementally.

Do not generate the entire system in one step.

For every phase:

1. Explain the architectural goal.
2. Create the minimum required code.
3. Add tests.
4. Run the tests.
5. Fix failures.
6. Update documentation.
7. Only then proceed to the next phase.

Before introducing a new technology, explain:

* why it is needed
* what problem it solves
* what alternative exists
* why it is appropriate for this learning project

The developer already has significant Java/Spring experience.

Therefore, when introducing Python concepts, explicitly highlight the equivalent Java/Spring concept where useful.

Examples:

FastAPI dependency injection
≈ Spring dependency injection
Pydantic model
≈ DTO + validation
SQLAlchemy
≈ JPA/Hibernate
pytest
≈ JUnit
asyncio
≈ asynchronous/non-blocking programming
Kafka consumer
≈ Spring Kafka @KafkaListener
Pydantic settings
≈ Spring configuration properties

Do not over-explain basic programming concepts.

Focus explanations on differences between the Java/Spring ecosystem and Python/FastAPI.

⸻

53. Final Learning Goal

At the end of this project, the developer should be able to draw the following architecture on a whiteboard and explain every major component:

                         React
                           │
                           ▼
                        FastAPI
                           │
                ┌──────────┴──────────┐
                │                     │
             MySQL                  Kafka
                                      │
                         ┌────────────┼────────────┐
                         ▼            ▼            ▼
                       AI Worker   Indexer     CRM Worker
                         │            │            │
                         ▼            ▼            ▼
                        LLM       Vector DB      CRM
                         │
                         ▼
                Client Intelligence
                         │
                         ▼
                  Retrieval Service
                         │
                         ▼
                    MCP Server
                         │
                         ▼
                  Claude / ChatGPT

The developer must be able to explain:

Why each component exists, what happens when it fails, how it scales, how it is secured, and what tradeoffs were made.

That is more important than simply having the application running.