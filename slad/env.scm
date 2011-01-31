(declare (usual-integrations))
;;;; Environments

;;; In this code, environments are flat, restricted to the variables
;;; actually referenced by the closure whose environment it is, and
;;; sorted by the bound names.  This canonical form much simplifies
;;; comparing and unioning them during the abstract analysis.

(define-structure (env (safe-accessors #t) (constructor %make-env))
  bindings)

(define (make-env bindings)
  (%make-env
   (sort
    bindings
    (lambda (binding1 binding2)
      (variable<? (car binding1) (car binding2))))))

(define (lookup exp env)
  (if (constant? exp)
      (constant-value exp)
      (let ((answer (assq exp (env-bindings env))))
	(if answer
	    (cdr answer)
	    (error "Variable not found" exp env)))))

(define (initial-slad-user-env)
  (make-env
   (map (lambda (primitive)
	  (cons (slad-primitive-name primitive) primitive))
	*primitives*)))

;;; Extending a SLAD environment involves destructuring the incoming
;;; argument structure according to the formal parameter tree of the
;;; closure whose environment is being extended.

(define (extend-env formal-tree arg env)
  (make-env (append-bindings (formal-bindings formal-tree arg)
			     (env-bindings env))))

(define (formal-bindings formal arg)
  (let walk ((name-tree (car formal))
	     (value-tree arg))
    (cond ((null? name-tree)
	   '())
	  ((symbol? name-tree)
	   (list (cons name-tree value-tree)))
	  ((and (pair? name-tree) (pair? value-tree))
	   (if (eq? (car name-tree) 'cons)
	       (append (walk (cadr name-tree) (car value-tree))
		       (walk (caddr name-tree) (cdr value-tree)))
	       (append (walk (car name-tree) (car value-tree))
		       (walk (cdr name-tree) (cdr value-tree)))))
	  (else
	   (error "Mismatched formal and actual parameter trees"
		  formal arg)))))

(define (append-bindings new-bindings old-bindings)
  (append new-bindings
	  (remove-from-bindings
	   (map car new-bindings)
	   old-bindings)))

(define (remove-from-bindings variables bindings)
  (filter (lambda (binding)
	    (not (member (car binding) variables)))
	  bindings))

(define (slad-env-map f env . envs)
  (make-env
   (map cons
	(map car (env-bindings env))
	(apply map
	       f
	       (map cdr (env-bindings env))
	       (map (lambda (env)
		      (map cdr (env-bindings env)))
		    envs)))))
