;;; ----------------------------------------------------------------------
;;; Copyright 2010-2011 National University of Ireland; 2012 Alexey Radul.
;;; ----------------------------------------------------------------------
;;; This file is part of DysVunctional Language.
;;; 
;;; DysVunctional Language is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU Affero General Public License as
;;; published by the Free Software Foundation, either version 3 of the
;;;  License, or (at your option) any later version.
;;; 
;;; DysVunctional Language is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;; 
;;; You should have received a copy of the GNU Affero General Public License
;;; along with DysVunctional Language.  If not, see <http://www.gnu.org/licenses/>.
;;; ----------------------------------------------------------------------

(declare (usual-integrations))
;;;; Alpha renaming

;;; Renaming all variables so that all bound names are unique is
;;; just a recursive descent on the structure of the code.  In fact,
;;; it doesn't even need to be too picky about the differences between
;;; various forms that do not bind names; it just has to catch the
;;; ones that do.

;;; The recursive traversal maintains an environment of which symbols
;;; currently in scope have been renamed to which others, and also
;;; which symbols are out of scope now but have been bound elsewhere
;;; in the program.  If a name being bound has not been bound before,
;;; it should be renamed to itself, otherwise to a fresh name.  In any
;;; case, it should be registered as a name that has been bound at
;;; some point so that other bindings elsewhere can avoid them.  This
;;; global uniqueness is necessary because various later operations
;;; may change the scopes of bound names.

(define (%alpha-rename program)
  (define stack (make-eq-hash-table))
  (define (ever-bound? name)
    (hash-table/get stack name #f))
  (define (in-scope? name)
    (pair? (hash-table/get stack name '())))
  (define (rename name)
    (car (hash-table/get stack name '())))
  (define (push! name rename)
    (hash-table/put!
     stack name (cons rename (hash-table/get stack name '()))))
  (define (pop! name)
    (hash-table/put!
     stack name (cdr (hash-table/get stack name '()))))
  (define (bind! name)
    (if (ever-bound? name)
        (push! name (make-name name))
        (push! name name)))
  (define unbind! pop!)
  (define (loop exp)
    (cond ((in-scope? exp) (rename exp))
          ((lambda-form? exp)
           (let ((names (cadr exp)))
             (for-each bind! names)
             (begin1
              `(lambda ,(map rename names)
                 ,@(loop (cddr exp)))
              (for-each unbind! names))))
          ((let-form? exp)
           (->let (loop (->lambda exp))))
          ((let-values-form? exp)
           (->let-values (loop (->lambda exp))))
          ((procedure-definition? exp)
           ;; Assume the definiendum is already unique
           (reconstitute-definition
            `(define ,(definiendum exp)
               ,(loop (definiens exp)))))
          ((type-definition? exp)
           ;; Type names are global anyway, in their own namespace
           exp)
          ((pair? exp)
           (cons (loop (car exp))
                 (loop (cdr exp))))
          (else exp)))
  (loop program))

;;; Checking whether two programs are alpha-renamings of each other is
;;; also a recursive traversal.

(define (alpha-rename? exp1 exp2)
  (let loop ((exp1 exp1)
             (exp2 exp2)
             (env '()))
    (cond ((assq exp1 env) => (lambda (bind) (equal? (cdr bind) exp2)))
          ((and (lambda-form? exp1) (lambda-form? exp2))
           (let* ((names1 (cadr exp1))
                  (body1 (cddr exp1))
                  (names2 (cadr exp2))
                  (body2 (cddr exp2))
                  (new-env (append (map cons names1 names2) env)))
             (loop body1 body2 new-env)))
          ((and (let-form? exp1) (let-form? exp2))
           (loop (->lambda exp1) (->lambda exp2) env))
          ((and (let-values-form? exp1) (let-values-form? exp2))
           (loop (->lambda exp1) (->lambda exp2) env))
          ;; Do I want to mess with the fact that the order of
          ;; definitions is semantically insignificant?
          ((and (begin-form? exp1) (begin-form? exp2))
           (let* ((proc-names1 (map definiendum (filter procedure-definition? exp1)))
                  (proc-names2 (map definiendum (filter procedure-definition? exp2)))
                  (type-names1 (map cadr (filter type-definition? exp1)))
                  (type-names2 (map cadr (filter type-definition? exp2)))
                  (new-env (append (map cons proc-names1 proc-names2)
                                   (map cons type-names1 type-names2)
                                   env)))
             (apply boolean/and
              (map (lambda (form1 form2)
                     (loop form1 form2 new-env))
                   exp1 exp2))))
          ;; At this point, the environment has already accounted
          ;; for the scope of the definitions
          ((and (procedure-definition? exp1) (procedure-definition? exp2))
           (let ((name1 (definiendum exp1))
                 (name2 (definiendum exp2)))
             (and (loop name1 name2 env)
                  (loop (definiens exp1) (definiens exp2) env))))
          ((and (pair? exp1) (pair? exp2))
           ;; This case handles type definitions correctly too, doesn't it?
           (and (loop (car exp1) (car exp2) env)
                (loop (cdr exp1) (cdr exp2) env)))
          (else (equal? exp1 exp2)))))

;;; Also, we can check whether a program is already alpha renamed
;;; (i.e. already has unique names) by looking to see whether it alpha
;;; renames to itself.

(define (unique-names? program)
  (equal? program (alpha-rename program)))

(define (local-names program)
  (define names '())
  (define (bound! name)
    (set! names (cons name names)))
  (define (loop exp)
    (cond ((lambda-form? exp)
           (for-each bound! (cadr exp))
           (loop (cddr exp)))
          ((let-form? exp)
           (loop (->lambda exp)))
          ((let-values-form? exp)
           (loop (->lambda exp)))
          ((procedure-definition? exp)
           ;; The procedure name is global; ignore it
           (loop (definiens exp)))
          ((type-definition? exp)
           ;; Type definitions create only global names
           'ok)
          ((pair? exp)
           (loop (car exp))
           (loop (cdr exp)))
          (else 'ok)))
  (loop program)
  (reverse names))
