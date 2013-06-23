;; The commandline script lands here

;; optimize n times; compile [via backend] are independent; execute
;; implies compile, but admits "interpreted fol" backend, for which
;; compiling is a no-op.

;; the mit scheme backend has a standalone option; Stalin, SBCL, and
;; Haskell are all standalone.

;; How to link to the compiled output afterwards?

(define backend-compilers
  `((mit-scheme . ,fol->mit-scheme)
    (floating-mit-scheme . ,fol->floating-mit-scheme)
    (standalone-mit-scheme . ,fol->standalone-mit-scheme)
    (stalin . ,fol->stalin)
    (common-lisp . ,fol->common-lisp)))

(define backend-runners
  `((mit-scheme . ,run-mit-scheme)
    (floating-mit-scheme . ,run-mit-scheme)
    (standalone-mit-scheme . #f)
    (stalin . #f)
    (common-lisp . ,run-common-lisp)))

(define-structure
  (modifiers
   (print-procedure
    (simple-unparser-method 'modifiers
                            (lambda (mod)
                              (list (modifiers-verb mod)
                                    (modifiers-backend mod)
                                    (modifiers-optimization mod)
                                    (modifiers-dumps mod)
                                    (modifiers-adverbs mod))))))
  verb backend optimization dumps adverbs)

(define (optimization-step modifiers)
  (repeat-stage fol-optimize (modifiers-optimization modifiers)))

(define (compilation-step modifiers)
  (if (eq? (modifiers-verb modifiers) 'optimize)
      (lambda args 'ok)
      (cdr (assq (modifiers-backend modifiers) backend-compilers))))

(define (execution-step modifiers)
  (if (eq? (modifiers-verb modifiers) 'run)
      (cdr (assq (modifiers-backend modifiers) backend-runners))
      (lambda args 'done)))

(define (dump-optimized? modifiers)
  (or (eq? (modifiers-verb modifiers) 'optimize)
      (memq 'optimized (modifiers-dumps modifiers))))

(define (parse-modifiers verb args)
  (define adverbs
    `((visibly . ,visibly)
      (volubly . ,volubly)
      (measuring-memory . ,measuring-memory)
      (watching-memory . ,watching-memory)
      (type-safely . ,type-safely)))
  (define the-mods (make-modifiers verb 'mit-scheme 1 '() '()))
  (define (backend choice)
    (if (memq choice (map car backend-compilers))
        (set-modifiers-backend! the-mods choice)
        (error "Unknown backend" choice)))
  (define (opt-count choice)
    (define counts '((never . 0) (once . 1) (twice . 2) (thrice . 3)))
    (set-modifiers-optimization! the-mods
                                 (if (assq choice counts)
                                     (cdr (assq choice counts))
                                     choice)))
  (define (dump stage)
    (if (memq stage '(optimized compiled))
        (set-modifiers-dumps! the-mods (cons stage (modifiers-dumps the-mods)))))
  (define (adverb stage)
    (set-modifiers-adverbs! the-mods (cons stage (modifiers-adverbs the-mods))))
  (let loop ((args args))
    (cond ((null? args) 'ok)
          ((eq? (car args) 'via)
           (backend (cadr args))
           (loop (cddr args)))
          ((eq? (car args) 'optimizing)
           (opt-count (cadr args))
           (loop (cddr args)))
          ((eq? (car args) 'dumping)
           (dump (cadr args))
           (loop (cddr args)))
          ((assq (car args) adverbs)
           (adverb (cdr (assq (car args) adverbs)))
           (loop (cdr args)))
          (else
           (error "Confusing option" (car args)))))
  (set-modifiers-dumps! the-mods (reverse (delete-duplicates (modifiers-dumps the-mods))))
  (set-modifiers-adverbs! the-mods (reverse (delete-duplicates (modifiers-adverbs the-mods))))
  the-mods)

;; fol [verb] file [via backend] [optimizing never|once|twice|thrice|n] [dumping <big-stage>] [adverb]*
(define (fol-main arg)
  (define (find-verb args)
    (cond ((null? args)
           (error "Need non-empty argument list"))
          ((memq (car args) '(optimize compile run))
           (car args))
          (else #f)))
  (let* ((args (with-input-from-string (string-append "(" arg ")") read))
         (verb (find-verb args))
         (args (if verb (cdr args) args))
         (verb (or verb 'run))
         (file (symbol->string (car args)))
         (args (cdr args))
         (modifiers (parse-modifiers verb args)))
    (pp `(,verb ,file ,modifiers))
    (let* ((program (with-input-from-file file read))
           (optimized-program (apply (optimization-step modifiers) program (modifiers-adverbs modifiers))))
      (if (dump-optimized? modifiers)
          (with-output-to-file (pathname-new-type file "opt")
            (lambda ()
              (pp program)
              (newline))))
      ((compilation-step modifiers) program file)
      (pp ((execution-step modifiers) file))
      (%exit 0))))
