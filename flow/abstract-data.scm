;; Abstract environments are just alists of bindings.  The
;; environments are expected to be flat, sorted, and precise, so that
;; they can be used effectively as keys in analysis bindings.
(define-structure (abstract-env (safe-accessors #t) (constructor %make-abstract-env))
  bindings)

(define (make-abstract-env bindings)
  (%make-abstract-env
   (sort
    bindings
    (lambda (binding1 binding2)
      (symbol<? (car binding1) (car binding2))))))

(define (abstract-lookup symbol env win lose)
  (let ((answer (assq symbol (abstract-env-bindings env))))
    (if answer
	(win (cdr answer))
	(lose))))

(define (env->abstract-env env)
  (make-abstract-env (flat-bindings env)))

(define (free-variables exp)
  (sort
   (cond ((symbol? exp) (list exp))
	 ((pair? exp)
	  (cond ((eq? (car exp) 'lambda)
		 (lset-difference eq? (free-variables (caddr exp))
				  (free-variables (cadr exp))))
		((eq? (car exp) 'cons)
		 (lset-union eq? (free-variables (cadr exp))
			     (free-variables (caddr exp))))
		(else
		 (lset-union eq? (free-variables (car exp))
			     (free-variables (cdr exp))))))
	 (else '()))
   symbol<?))

(define (restrict-to symbols abstract-env)
  (make-abstract-env
   (filter (lambda (binding)
	     (memq (car binding) symbols))
	   (abstract-env-bindings abstract-env))))

;;; An abstract closure is just a normal closure with an abstract
;;; environment that is correctly restricted to include only the free
;;; variables in that closure's body.
(define (make-abstract-closure formal body abstract-env)
  (make-closure formal body
   (restrict-to (free-variables `(lambda ,formal ,body)) abstract-env)))

(define (extend-abstract-env formal arg abstract-env)
  (make-abstract-env
   (append-bindings (formal-bindings formal arg)
		    (abstract-env-bindings abstract-env))))

(define (abstract-equal? thing1 thing2)
  (cond ((eqv? thing1 thing2)
	 #t)
	((and (closure? thing1) (closure? thing2))
	 (and (equal? (closure-body thing1)
		      (closure-body thing2))
	      ;; TODO alpha-renaming closures?
	      (equal? (closure-formal thing1)
		      (closure-formal thing2))
	      (abstract-equal? (closure-env thing1)
			       (closure-env thing2))))
	((and (pair? thing1) (pair? thing2))
	 (and (abstract-equal? (car thing1) (car thing2))
	      (abstract-equal? (cdr thing1) (cdr thing2))))
	((and (abstract-env? thing1) (abstract-env? thing2))
	 (abstract-equal? (abstract-env-bindings thing1)
			  (abstract-env-bindings thing2)))
	(else #f)))

(define (abstract-union thing1 thing2)
  (error "abstract-union unimplemented"))

(define abstract-boolean (list 'abstract-boolean))
(define (abstract-boolean? thing)
  (eq? thing abstract-boolean))
(define abstract-real (list 'abstract-real))
(define (abstract-real? thing)
  (eq? thing abstract-real))
(define abstract-all (list 'abstract-all))
(define (abstract-all? thing)
  (eq? thing abstract-all))

(define-structure (analysis (safe-accessors #t))
  bindings)

(define (analysis-lookup exp env analysis win lose)
  (let loop ((bindings (analysis-bindings analysis)))
    (if (null? bindings)
	(lose)
	(if (and (equal? exp (caar bindings))
		 (abstract-equal? env (cadar bindings)))
	    (win (caddar bindings))
	    (loop (cdr bindings))))))

(define (same-analysis-binding? binding1 binding2)
  (abstract-equal? binding1 binding2))

(define (same-analysis? ana1 ana2)
  (lset= same-analysis-binding? (analysis-bindings ana1)
	 (analysis-bindings ana2)))
