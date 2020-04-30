;;; Code:  -*- lexical-binding: t; -*-

(require 'ansi-color)
(require 'cl-lib)
(require 'company)

(defgroup company-elixir nil
  "Company-Elixir group."
  :prefix "company-elixir-"
  :group 'company-elixir)

(defcustom company-elixir-iex-command "iex -S mix"
  "Command used to start iex."
  :type 'string
  :group 'company-elixir)

(defcustom company-elixir-major-mode #'elixir-mode
  "Major mode for company-elixir."
  :type 'function
  :group 'company-elixir)

(defun company-elixir--project-root ()
  "Find the root of the current mix project."
  (let ((closest-path (or buffer-file-name default-directory)))
    (if (string-match-p (regexp-quote "apps") closest-path)
        (let* ((potential-umbrella-root-parts (butlast (split-string closest-path "/apps/")))
               (potential-umbrella-root (mapconcat #'identity potential-umbrella-root-parts ""))
               (umbrella-app-root (mix--find-closest-mix-file-dir potential-umbrella-root)))
          (or umbrella-app-root (mix--find-closest-mix-file-dir closest-path)))
      (company-elixir--find-closest-mix-file-dir closest-path))))

(defun company-elixir--find-closest-mix-file-dir (path)
  "Find the closest mix file to the current buffer PATH."
    (let ((root (locate-dominating-file path "mix.exs")))
    (when root
      (file-truename root))))

(defconst company-elixir--script-name "company_elixir_script.exs" "Name of the iex script file.")

(defconst company-elixir--directory
  (if load-file-name (file-name-directory load-file-name) default-directory)
  "Iex script directory.")

(defconst company-elixir--evaluator-init-code
  (with-temp-buffer
    (insert-file-contents (concat company-elixir--directory company-elixir--script-name))
    (buffer-string))
  "Iex evaluator code.")

(defvar company-elixir--last-completion nil "The last expression that was completed.")

(defvar company-elixir--process nil "Iex process.")

(defvar company-elixir--callback nil "Company callback to return candidates to.")

(defun company-elixir--init-code()
  "Read iex evaluator if it's not read or return if it's read."
  (or company-elixir--evaluator-init-code
      (setq company-elixir--evaluator-init-code (company-elixir--read-init-code))))

(defun company-elixir--start-iex-process ()
  "Start iex process."
  (let* ((process-name "iex")
         (default-directory (company-elixir--project-root)))
    (setq company-elixir--process (start-process-shell-command process-name "*iex*" company-elixir-iex-command))
    (set-process-query-on-exit-flag company-elixir--process nil)
    (process-send-string company-elixir--process company-elixir--evaluator-init-code)
    (set-process-filter company-elixir--process #'company-elixir--candidates-filter)))

(defun company-elixir--candidates-filter (_process output)
  "Filter OUTPUT from iex process and redirect them to company."
  (let ((output-without-ansi-chars (ansi-color-apply output)))
    (set-text-properties 0 (length output-without-ansi-chars) nil output-without-ansi-chars)
    (let ((output-without-iex (car (split-string output-without-ansi-chars "iex"))))
      (if (string-match "\\[" output-without-iex)
          (let ((candidates (split-string output-without-iex "\[\],[ \f\t\n\r\v']+" t)))
            (company-elixir--return-candidates candidates))))))

(defun company-elixir--find-candidates(expr)
  "Send request for completion to iex process with EXPR."
  (unless company-elixir--process
    (company-elixir--start-iex-process))
  (process-send-string company-elixir--process
                       (concat "CompanyElixirServer.expand('" expr "')\n")))

(defun company-elixir (command &optional arg &rest ignored)
  "Completion backend for company-mode."
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-elixir))
    (prefix (and (eq major-mode company-elixir-major-mode)
                 (company-elixr--get-prefix)))
    (candidates (cons :async
                      (lambda (callback)
                        (setq company-elixir--callback callback)
                        (setq company-elixir--last-completion arg)
                        (company-elixir--find-candidates arg))))
    (annotation "")))

(defun company-elixir--return-candidates (candidates)
  "Return CANDIDATES to company-mode."
  (if company-elixir--callback
      (let* ((prefix (cond
                      ((string-match-p "\\.$" company-elixir--last-completion) company-elixir--last-completion)
                      ((not (string-match-p "\\." company-elixir--last-completion)) "")
                      (t company-elixir--last-completion)))
             (completions (mapcar (lambda(var) (concat prefix var)) candidates)))
        (print prefix)
        (print completions)
        (funcall company-elixir--callback completions))))

(defun company-elixr--get-prefix ()
  "Return the expression under the cursor."
  (if (or (looking-at "\s") (eolp))
      (let (p1 p2 (skip-chars "-_A-Za-z0-9.?!@:"))
        (save-excursion
          (skip-chars-backward skip-chars)
          (setq p1 (point))
          (skip-chars-forward skip-chars)
          (setq p2 (point))
          (buffer-substring-no-properties p1 p2)))))

(defun company-elixir-hook()
  "Add elixir-company to company-backends."
  (add-to-list (make-local-variable 'company-backends)
               'company-elixir))

(provide 'company-elixir)
;;; company-elixir ends here
