(define (tidy-non-soundness program)
  (cond ((not (equal? (fol-eval program)
		      (fol-eval (tidy (alpha-rename program)))))
	 `(not (equal? ,(fol-eval program)
		       (after-tidy ,(fol-eval (tidy (alpha-rename program)))))))
	(else #f)))

(in-test-group
 fol

 (define-each-check
   (equal? '(cons 1 2) (replace-free-occurrences 'foo 'bar '(cons 1 2)))
   (equal? '(let ((x y)) 1) (replace-free-occurrences 'foo 'bar '(let ((x y)) 1)))
   (equal? '(let ((x bar)) 1) (replace-free-occurrences 'foo 'bar '(let ((x foo)) 1)))
   (equal? '((cons 1 2)) (replace-free-occurrences 'foo 'bar '((cons 1 2))))
   (equal? '(lambda () (cons 1 2)) (replace-free-occurrences 'foo 'bar '(lambda () (cons 1 2))))
   )

 (define-each-check
   (equal?
    '(begin
       (vector-ref (vector 1 2) 0))
    (structure-definitions->vectors
     '(begin
        (define-structure foo bar baz)
        (foo-bar (make-foo 1 2)))))

   (lset= eq? '(c a) (feedback-vertex-set '((a b c d) (b a) (c d) (d c) (e a))))

   (lset= eq? '(a c d)
    (feedback-vertex-set
     ;; This is G from the comments in feedback-vertex-set.scm
     '((a b) (b a c) (c a e) (d c e) (e d))))

   (not (tidy-non-soundness
	 ;; Carelessly inlining y will change the scope of x
	 '(let ((x (vector 1 2)))
	    (cons x (cons x (let ((y (vector 3 x))
				  (x (vector 4)))
			      (cons x (cons x (vector-ref (vector-ref y 1) 1)))))))))

   (alpha-rename?
    '(if (< (real 1) (real 2))
         (real 0)
         (+ (real 1) (real 2)))
    (fol-optimize
     '(car
       (let ((x (let ((y (+ (real 1) (real 2))))
                  (cons y (vector)))))
         (if (< (real 1) (real 2))
             (cons (real 0) (vector))
             x)))))

   (alpha-rename?
    '(if (< (real 1) (real 2))
         (real 0)
         (+ (real 1) (real 2)))
    (fol-optimize
     '(car
       (let ((x (let ((y (+ (real 1) (real 2))))
                  (cons y (cons y (vector))))))
         (if (< (real 1) (real 2))
             (cons (real 0) (cons (real 1) (vector)))
             x)))))

   (alpha-rename?
    '(+ (real 1) (real 2))
    (fol-optimize
     '(car
       (cdr
        (let ((x (let ((y (+ (real 1) (real 2))))
                   (cons y (cons y (vector))))))
          (if (< (real 1) (real 2))
              (cons (real 0) x)
              (cons (real 1) x)))))))

   (alpha-rename?
    '(let ((y (+ (real 1) (real 2))))
       (if (< (real 1) (real 2))
           (+ y (real 0))
           y))
    (fol-optimize
     '(let ((x (let ((y (+ (real 1) (real 2))))
                 (cons (+ y (real 0)) (cons y (vector))))))
        (if (< (real 1) (real 2))
            (car x)
            (car (cdr x))))))

   (equal? #t (fol-optimize '#t))
   (equal? #f (fol-optimize '#f))

   ;; Elimination should not get confused by procedures that return
   ;; multiple things only one of which is needed.
   (check-program-types
    (eliminate-intraprocedural-dead-variables
     '(begin
        (define (foo)
          (argument-types (values real real))
          (values 1 2))
        (let-values (((x y) (foo)))
          y))))

   (equal? #f (procedure-definitions->program
               (program->procedure-definitions #f)))

   (equal?
    '(begin
       (define (fact n)
         (argument-types real real)
         (if (= n 0)
             1
             (* n (fact (- n 1)))))
       (fact (real 5)))
    (interprocedural-dead-code-elimination
     '(begin
        (define (fact dead n)
          (argument-types real real real)
          (if (= n 0)
              1
              (* n (fact dead (- n 1)))))
        (fact (real 1) (real 5)))))

   (equal?
    '(begin
       (define (fact n)
         (argument-types real real)
         (if (= n 0)
             1
             (* n (fact (- n 1)))))
       (fact (real 5)))
    (tidy
     (interprocedural-dead-code-elimination
      '(begin
         (define (fact n)
           (argument-types real (values real real))
           (if (= n 0)
               (values 0 1)
               (let-values (((dead n-1!) (fact (- n 1))))
                 (values
                  dead
                  (* n n-1!)))))
         (let-values (((dead n!) (fact (real 5))))
           n!)))))

   (equal?
    '(let ((x (real 5)))
       (let ((y (+ x 2)))
         (+ y y)))
    (intraprocedural-cse
     '(let ((x (real 5)))
        (let ((y (+ x 2)))
          (let ((z (+ x 2)))
            (+ y z))))))

   (equal?
    '(let ((x (real 5)))
       ;; I could improve this by hacking intraprocedural-cse more,
       ;; or I can just let dead code elimination deal with it.
       (let ((y (+ x 2)) (z (+ x 2)))
         (+ y y)))
    (intraprocedural-cse
     '(let ((x (real 5)))
        (let ((y (+ x 2)) (z (+ x 2)))
          (+ y z)))))

   (equal?
    '(let ((x (real 5)))
       (+ x x))
    (intraprocedural-cse
     '(let ((x (real 5)))
        (let ((y (+ x 0)))
          (let ((z (+ x 0)))
            (+ y z))))))

   ;; TODO Abstract the test pattern "CSE didn't eliminate this thing
   ;; it shouldn't have eliminated"?
   (equal?
    '(let ((x (real 5)))
       (let ((y (+ x 3)))
         y))
    (intraprocedural-cse
     '(let ((x (real 5)))
        (let ((y (+ x 3)))
          y))))

   (equal?
    '(let ((x (real 5)))
       (let ((w (let ((y (+ x 3))) y)))
         w))
    (intraprocedural-cse
     '(let ((x (real 5)))
        (let ((w (let ((y (+ x 3))) y)))
          w))))

   (equal?
    '(let ((x (real 5)))
       (let ((w (let ((y (+ x 3))) y)))
         (let ((z (+ x 3)))
           (+ w z))))
    (intraprocedural-cse
     '(let ((x (real 5)))
        (let ((w (let ((y (+ x 3))) y)))
          (let ((z (+ x 3)))
            (+ w z))))))

   (equal?
    '(let ((x (real 5)))
       (let ((w (let ((y (+ x 3))) y)))
         (let ((z (+ x 3)))
           (+ w (* z z)))))
    (intraprocedural-cse
     '(let ((x (real 5)))
        (let ((w (let ((y (+ x 3))) y)))
          (let ((z (+ x 3)))
            (let ((u (+ x 3)))
              (+ w (* z u))))))))

   (equal?
    '(begin
       (define (op a b)
         (argument-types real real (values real real))
         (values (+ a b) (- a b)))
       (let-values (((x y) (op 1 2)))
         (+ x y)))
    (intraprocedural-cse
     '(begin
        (define (op a b)
          (argument-types real real (values real real))
          (values (+ a b) (- a b)))
        (let-values (((x y) (op 1 2)))
          (+ x y)))))

   (equal?
    '(let ((x (real 3)))
       (let-values
           (((x+1 something)
             (if (> (real 2) 1)
                 (values (+ x 1) (+ x 4))
                 (values (+ x 1) (+ x 3)))))
         (* something (+ x+1 x+1))))
    (intraprocedural-cse
     '(let ((x (real 3)))
        (let-values (((x+1 something)
                      (if (> (real 2) 1)
                          (values (+ x 1) (+ x 4))
                          (values (+ x 1) (+ x 3)))))
          (let ((y (+ x 1)))
            (* something (+ y x+1)))))))

   (equal?
    '(let ((x (read-real))
           (y (read-real)))
       (+ x y))
    (intraprocedural-cse
     '(let ((x (read-real))
            (y (read-real)))
        (+ x y))))

   (equal?
    '(begin
       (define (my-read)
         (read-real))
       (let ((x (my-read))
             (y (my-read)))
         (+ x y)))
    (intraprocedural-cse
     '(begin
        (define (my-read)
          (read-real))
        (let ((x (my-read))
              (y (my-read)))
          (+ x y)))))

   ;; TODO An example for interprocedural CSE
   #;
   (begin
     (define (double-fact n1 n2)
       (argument-types real real (values real real))
       (if (<= n1 1)
           (values n1 n2)
           (let-values (((n1-1! n2-1!) (double-fact (- n1 1) (- n2 1))))
             (values (* n1 n1-1!) (* n2 n2-1!)))))
     (let ((x (real 5)))
       (let-values (((a1 a2) (double-fact x x)))
         (cons a1 a2))))

   ))