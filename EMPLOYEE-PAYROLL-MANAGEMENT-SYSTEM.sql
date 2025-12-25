-- =====================================================
-- EMPLOYEE PAYROLL MANAGEMENT SYSTEM
-- Domain: HR / Corporate
-- PL/SQL Concepts: Package, Procedure, Function, Cursor, Trigger
-- =====================================================



-- 2. Create Tables
CREATE TABLE departments (
    dept_id NUMBER PRIMARY KEY,
    dept_name VARCHAR2(50) NOT NULL UNIQUE
);

CREATE TABLE employees (
    emp_id NUMBER PRIMARY KEY,
    emp_name VARCHAR2(100) NOT NULL,
    dept_id NUMBER,
    basic_salary NUMBER(10,2) NOT NULL CHECK (basic_salary > 0),
    hra_percent NUMBER(5,2) DEFAULT 30,     -- 30% of basic
    bonus_percent NUMBER(5,2) DEFAULT 10,   -- 10% of basic
    tax_percent NUMBER(5,2) DEFAULT 10,     -- 10% tax on gross
    join_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_dept FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

CREATE TABLE salary_details (
    sal_id NUMBER PRIMARY KEY,
    emp_id NUMBER NOT NULL,
    month_year VARCHAR2(7),                 -- Format: YYYY-MM e.g., 2025-12
    gross_salary NUMBER(12,2),
    tax_deducted NUMBER(12,2),
    net_salary NUMBER(12,2),
    processed_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_emp_sal FOREIGN KEY (emp_id) REFERENCES employees(emp_id),
    CONSTRAINT uq_emp_month UNIQUE (emp_id, month_year)
);

-- 3. Sequences
CREATE SEQUENCE seq_emp START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_sal START WITH 1 INCREMENT BY 1 NOCACHE;

-- 4. Package Specification
CREATE OR REPLACE PACKAGE payroll_pkg AS
    -- Function to calculate tax amount
    FUNCTION fn_calc_tax(p_gross NUMBER, p_tax_percent NUMBER) RETURN NUMBER;
    
    -- Procedure to calculate and generate salary for one employee
    PROCEDURE proc_calculate_salary(
        p_emp_id IN NUMBER,
        p_month_year IN VARCHAR2
    );
    
    -- Procedure to generate payslips for all employees in a month
    PROCEDURE proc_generate_monthly_payslip(p_month_year IN VARCHAR2);
    
    -- Cursor for department-wise salary report
    CURSOR cur_dept_report(p_month_year VARCHAR2) IS
        SELECT d.dept_name,
               COUNT(e.emp_id) AS total_employees,
               SUM(sd.net_salary) AS total_net_salary,
               AVG(sd.net_salary) AS avg_net_salary
        FROM departments d
        JOIN employees e ON d.dept_id = e.dept_id
        JOIN salary_details sd ON e.emp_id = sd.emp_id
        WHERE sd.month_year = p_month_year
        GROUP BY d.dept_name
        ORDER BY total_net_salary DESC;
END payroll_pkg;
/

-- 5. Package Body
CREATE OR REPLACE PACKAGE BODY payroll_pkg AS

    -- Function: Calculate Tax
    FUNCTION fn_calc_tax(p_gross NUMBER, p_tax_percent NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN (p_gross * p_tax_percent / 100);
    END fn_calc_tax;

    -- Procedure: Calculate salary for one employee
    PROCEDURE proc_calculate_salary(
        p_emp_id IN NUMBER,
        p_month_year IN VARCHAR2
    ) IS
        v_basic employees.basic_salary%TYPE;
        v_hra NUMBER;
        v_bonus NUMBER;
        v_gross NUMBER;
        v_tax NUMBER;
        v_net NUMBER;
    BEGIN
        -- Get employee details
        SELECT basic_salary, hra_percent, bonus_percent, tax_percent
        INTO v_basic, v_hra, v_bonus, v_tax
        FROM employees
        WHERE emp_id = p_emp_id;
        
        -- Calculations
        v_hra := v_basic * v_hra / 100;
        v_bonus := v_basic * v_bonus / 100;
        v_gross := v_basic + v_hra + v_bonus;
        v_tax := fn_calc_tax(v_gross, v_tax);
        v_net := v_gross - v_tax;
        
        -- Insert or update salary_details
        MERGE INTO salary_details sd
        USING DUAL
        ON (sd.emp_id = p_emp_id AND sd.month_year = p_month_year)
        WHEN MATCHED THEN
            UPDATE SET gross_salary = v_gross,
                       tax_deducted = v_tax,
                       net_salary = v_net,
                       processed_date = SYSDATE
        WHEN NOT MATCHED THEN
            INSERT (sal_id, emp_id, month_year, gross_salary, tax_deducted, net_salary)
            VALUES (seq_sal.NEXTVAL, p_emp_id, p_month_year, v_gross, v_tax, v_net);
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Salary processed for Employee ID ' || p_emp_id || 
                             ' | Net Salary: ₹' || v_net);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Employee not found!');
    END proc_calculate_salary;

    -- Procedure: Generate payslips for all employees in a month
    PROCEDURE proc_generate_monthly_payslip(p_month_year IN VARCHAR2) IS
        CURSOR cur_all_emp IS SELECT emp_id FROM employees;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== Generating Payslips for ' || p_month_year || ' ===');
        FOR rec IN cur_all_emp LOOP
            proc_calculate_salary(rec.emp_id, p_month_year);
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('Monthly payslip generation completed!');
    END proc_generate_monthly_payslip;

END payroll_pkg;
/

-- 6. Trigger: Audit salary changes
CREATE OR REPLACE TRIGGER trg_audit_salary
AFTER UPDATE OF basic_salary, hra_percent, bonus_percent, tax_percent ON employees
FOR EACH ROW
BEGIN
    DBMS_OUTPUT.PUT_LINE('AUDIT: Salary components updated for Employee ' || :NEW.emp_id ||
                         ' | Old Basic: ' || :OLD.basic_salary || ' → New: ' || :NEW.basic_salary);
END trg_audit_salary;
/

-- =============================================
-- TEST DATA & DEMO
-- =============================================

-- Insert Departments
INSERT INTO departments (dept_id, dept_name) VALUES (1, 'IT');
INSERT INTO departments (dept_id, dept_name) VALUES (2, 'HR');
INSERT INTO departments (dept_id, dept_name) VALUES (3, 'Sales');

-- Insert Employees
INSERT INTO employees (emp_id, emp_name, dept_id, basic_salary) 
VALUES (seq_emp.NEXTVAL, 'Amit Sharma', 1, 50000);

INSERT INTO employees (emp_id, emp_name, dept_id, basic_salary, hra_percent, bonus_percent) 
VALUES (seq_emp.NEXTVAL, 'Priya Singh', 1, 60000, 40, 15);

INSERT INTO employees (emp_id, emp_name, dept_id, basic_salary) 
VALUES (seq_emp.NEXTVAL, 'Rahul Kumar', 2, 45000);

INSERT INTO employees (emp_id, emp_name, dept_id, basic_salary) 
VALUES (seq_emp.NEXTVAL, 'Neha Gupta', 3, 55000);

COMMIT;

-- Demo: Generate payslips for December 2025
BEGIN
    payroll_pkg.proc_generate_monthly_payslip('2025-12');
END;
/

-- Demo: Individual payslip calculation
BEGIN
    payroll_pkg.proc_calculate_salary(1, '2025-12');
END;
/

-- Demo: Department-wise Salary Report (Cursor)
DECLARE
    v_dept_name departments.dept_name%TYPE;
    v_emp_count NUMBER;
    v_total_net NUMBER;
    v_avg_net NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Department-wise Salary Report - Dec 2025 ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('Department', 15) || RPAD('Employees', 12) || 
                         RPAD('Total Net', 15) || 'Avg Net');
    DBMS_OUTPUT.PUT_LINE('---------------------------------------------------');
    
    OPEN payroll_pkg.cur_dept_report('2025-12');
    LOOP
        FETCH payroll_pkg.cur_dept_report INTO v_dept_name, v_emp_count, v_total_net, v_avg_net;
        EXIT WHEN payroll_pkg.cur_dept_report%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(RPAD(v_dept_name, 15) || RPAD(v_emp_count, 12) || 
                             RPAD(v_total_net, 15) || v_avg_net);
    END LOOP;
    CLOSE payroll_pkg.cur_dept_report;
END;
/

-- Demo: Trigger Test (Change basic salary)
UPDATE employees SET basic_salary = 70000 WHERE emp_id = 1;

-- Final Payslip View
SELECT e.emp_name, d.dept_name, sd.month_year, sd.gross_salary, sd.tax_deducted, sd.net_salary
FROM salary_details sd
JOIN employees e ON sd.emp_id = e.emp_id
JOIN departments d ON e.dept_id = d.dept_id
WHERE sd.month_year = '2025-12'
ORDER BY e.emp_id;

BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('EMPLOYEE PAYROLL SYSTEM READY!');
    DBMS_OUTPUT.PUT_LINE('All features demonstrated successfully.');
    DBMS_OUTPUT.PUT_LINE('========================================');
END;
/