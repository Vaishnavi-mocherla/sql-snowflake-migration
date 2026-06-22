# Financial Planning System Migration: SQL Server to Snowflake

## Overview

This project demonstrates the migration of a SQL Server–based financial planning and consolidation system to Snowflake.

The objective was to preserve the original business workflows while redesigning SQL Server-specific implementations using Snowflake-native patterns and scalable data warehouse design principles.

The migrated solution includes financial consolidation, cost allocation, intercompany reconciliation, hierarchy processing, and supporting schema components.

---

## Project Structure

```text
src/
├── Functions/
├── Schema/
├── StoredProcedures/
├── Tables/
├── UserDefinedTypes/
└── Views/
```

The repository contains the migrated Snowflake implementation along with supporting database objects required for execution.

---

## Migration Highlights

Several SQL Server-specific features were redesigned to align with Snowflake's architecture.

| SQL Server Feature      | Snowflake Implementation |
| ----------------------- | ------------------------ |
| HIERARCHYID             | Recursive CTEs           |
| XML                     | VARIANT                  |
| Table Variables         | Temporary Tables         |
| Cursor-Based Processing | Set-Based Operations     |
| Computed Columns        | Explicit Stored Values   |

The migration focused on preserving business logic while improving maintainability and scalability within Snowflake.

---

## Core Workflows

### Budget Consolidation

Implemented hierarchical budget consolidation using recursive hierarchy traversal and rollup aggregation.

Features include:

* Multi-level cost center hierarchy processing
* Budget rollup calculations
* Consolidation journal generation
* Intercompany elimination
* Rerun protection and idempotency controls

### Cost Allocation Engine

Implemented a rule-driven allocation framework for distributing financial data across target entities.

Features include:

* Allocation rule management
* Semi-structured target definitions using VARIANT
* Dynamic target expansion using FLATTEN
* Percentage-based allocation processing
* Audit-friendly allocation tracking

### Intercompany Reconciliation

Implemented an intercompany reconciliation workflow to identify and resolve balance mismatches across entities.

Features include:

* Variance detection
* Tolerance-based reconciliation logic
* Pairing of intercompany accounts
* Adjustment journal generation
* Reconciliation reporting outputs

---

## Technical Design Decisions

Key architectural decisions during migration included:

* Replacing procedural logic with set-based processing where possible
* Reconstructing hierarchy logic using recursive CTEs
* Leveraging Snowflake VARIANT for semi-structured data
* Simplifying platform-specific SQL Server constructs
* Maintaining schema fidelity where required for business workflows

---

## Validation Approach

The migrated workflows were validated using synthetic financial datasets covering:

* Hierarchical aggregation scenarios
* Revenue and expense rollups
* Cost allocation processing
* Intercompany elimination
* Reconciliation workflows
* Journal generation logic

Testing focused on ensuring functional correctness while preserving expected business outcomes.

---

## Technologies

* Snowflake
* SQL
* Recursive CTEs
* VARIANT / FLATTEN
* Financial Data Modeling
* Data Warehouse Design

---

## Future Enhancements

Potential improvements include:

* Advanced allocation strategies
* Enhanced reconciliation reporting
* Detailed partner-entity matching
* Monitoring and logging framework
* Automated validation and testing pipelines

---

## Author

Vaishnavi Mocherla
