;;; stm32.el --- Support for the STM32 mircocontrollers programming
;; 
;; Filename: stm32.el
;; Description:
;; Author: Alexander Lutsai <s.lyra@ya.ru>
;; Maintainer:
;; Created: 05 Sep 2016
;; Version: 0.01
;; Package-Requires: ()
;; Last-Updated: 11 Sep 2016
;;           By: Alexander Lutsai
;;     Update #: 0
;; URL:
;; Doc URL:
;; Keywords:
;; Compatibility:
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;; Commentary:
;;
;; Required:
;; 1) CEDET
;; 2) python
;; 3) cmake
;; 4) st-link https://github.com/texane/stlink
;; //4) https://github.com/SL-RU/STM32CubeMX_cmake
;;
;; 1) (require 'stm32)
;; 2) Create STM32CubeMx project and generate it for SW4STM32 toolchain
;; 3) M-x stm32-new-project RET *select CubeMX project path*
;; 4) open main.c
;; 5) C-c . C to compile
;; 6) connect stlink to your PC
;; 7) stm32-run-st-util to start gdb server
;; 8) start GDB debugger with stm32-start-gdb
;; 9) in gdb) "load" to upload file to MC and "cont" to run.For more see https://github.com/texane/stlink
;; 5) good luck!
;;
;; To load that project after restart you need to (stm32-load-project).Or you can add to your init file (stm32-load-all-projects) for automatic loading.
;;
;; For normal file & header completion you need to (global-semantic-idle-scheduler-mode 1) in your init file.
;;
;; After CubeMx project regeneration or adding new libraries or new sources you need to do stm32-cmake-build
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;; Change Log:
;; 
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;; 
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 
;;; Code:

(defgroup stm32 nil
  "STM32 projects integration"
  :group 'development)

(defcustom stm32-st-util-command "st-util"
  "The command to use to run st-util."
  :group 'stm32
  :type 'string)

(defcustom stm32-template-files `("CubeMX2_cmake.py"
				  "CMakeIgnore.txt"
				  "CMakeLists.txt")
  "Name of script for generating makefiles."
  :group 'stm32
  :type 'string)

(defcustom stm32-template (concat user-emacs-directory
				  "stm32/STM32CubeMX_cmake/")
  "Directory with scripts for generating makefiles."
  :group 'stm32
  :type 'string)

(defcustom stm32-gdb-start
  "arm-none-eabi-gdb -iex \"target extended-remote localhost:4242\" -i=mi "
  "Command to run gdb for gud."
  :group 'stm32
  :type 'string)

(defcustom stm32-cubemx
  "~/STM32CubeMX/STM32CubeMX"
  "Path to stm32CubeMx binary."
  :group 'stm32
  :type 'string)

(defcustom stm32-template-project
  "(ede-add-project-to-global-list
 (ede-compdb-project \"%s\"
                     :name \"%s\"
		     :file \"%s\"
		     :build-command \"%s\"
		     :compdb-file \"%s\"))"

  "Template project.el for generation project.el."
  :group 'stm32
  :type 'string)

(defcustom stm32-build-dir
  "build"
  "Directory for cmake build."
  :group 'stm32
  :type 'string)


(defun stm32-get-project ()
  "Return ede project for stm32-get-project-root-dir & stm32-get-project-name."
  (let* ((fname (or (buffer-file-name (current-buffer)) default-directory))
	 (current-dir (file-name-directory fname))
         (prj (ede-current-project current-dir)))
    (if (null prj)
	(user-error "Buffer has no project")
      prj)))

(defun stm32-get-project-root-dir ()
  "Return path of current project."
  (let* ((prj (stm32-get-project))
	 (dir (ede-project-root-directory prj)))
    (message (concat "Project dir: " dir))
    dir))

(defun stm32-get-project-name ()
  "Return path of current project."
  (let* ((prj (stm32-get-project))
	 (name (ede-name prj)))
    (message (concat "Project name: " name))
    name))

(defun stm32-generate-project (path name)
  "Generate project.el for EDE in PATH with name NAME."
  (when path
    (let ((pth (concat path "project.el")))
      (when (file-exists-p pth)
	(delete-file pth))
      (with-temp-buffer
	(insert (format
		 stm32-template-project
		 name
		 name
		 (concat path (first (last stm32-template-files)))
		 (concat "cd " path stm32-build-dir "; make;")
		 (concat path stm32-build-dir "/compile_commands.json")))
	(write-file pth)))))

(defun stm32-cmake-build (&optional path)
  "Execute cmake and create build directory if not exists.  Use existing project path's or use optional arg PATH."
  (interactive)
  (let ((dir (or path (stm32-get-project-root-dir))))
    (when dir
      (let ((pth (concat dir stm32-build-dir)))
	(when (not (file-directory-p pth))
	  (make-directory pth))
	(when (file-directory-p pth)
	  (message "cmake project...")
	  (async-shell-command
	   (concat "cd " pth "; cmake ..;"))
	  (message "and make...")
	  (compile
	   (concat "cd " pth "; cmake ..; make;"))
	  (message "ok"))))))

(defun stm32-load-project (&optional path)
  "Load project.el of current project.PATH is path to project folder."
  (interactive)
  (let ((dir (if path
		 path
	       (stm32-get-project-root-dir))))
    (when dir
      (let ((pth (concat dir "/project.el")))
	(message pth)
	(when (file-exists-p pth)
	  (progn
	    (message "file exists")
	    (load-file pth)
	    (message (concat pth " loaded"))))))))

(defun stm32-new-project ()
  "Create new stm32  project from existing code."
  (interactive)
  (let* ((fil (read-directory-name "Select STM32CubeMx directory:"))
	 (nam (first (last (s-split "/" fil) 2)))) 
    (when (file-exists-p fil)
      (when (y-or-n-p (concat "Create project " nam
			      " in " fil "? "))
	(progn
	  (message (concat "copying " stm32-template))
	  (dolist (x stm32-template-files)
	    (copy-file (concat stm32-template x) (concat fil x) t)
	    (message (concat "copied " (concat fil x))))
	  (message "First build")
	  (stm32-cmake-build fil) ;build
	  (message "Generate project")
	  (stm32-generate-project fil nam)
	  (ede-check-project-directory fil)
	  (message "Add to ede projects custom")
	  (stm32-load-project fil)
	  (message "done")
	  )))))

(defun stm32-run-st-util ()
  "Run st-util gdb server."
  (interactive)
  (let ((p (get-buffer-process "*st-util*")))
    (when p
      (if (y-or-n-p "Kill currently running st-util? ")
	  (interrupt-process p)
	(user-error "St-util already running!"))))
  
  (sleep-for 1) ;wait for st-util being killed
  
  (with-temp-buffer "*st-util*"
		    
		    (async-shell-command stm32-st-util-command
					 "*st-util*"
					 "*Messages*")
		    ;;(pop-to-buffer "*st-util*")
		    ))
(defun stm32-start-gdb ()
  "Strart gud arm-none-eabi-gdb and connect to st-util."
  (interactive)
  (let ((dir (stm32-get-project-root-dir))
	(name (stm32-get-project-name))
	(p (get-buffer-process "*st-util*")))
    (when (not p)
      (stm32-run-st-util))
    (when dir
      (let ((pth (concat dir stm32-build-dir "/" name ".elf")))
	(when (file-exists-p pth)
	  (progn
	    (message pth)
	    (gdb (concat stm32-gdb-start pth) )))))))

(defun stm32-load-all-projects ()
  "Read all directories from 'ede-project-directories and load project.el."
  (interactive)
  (or (eq ede-project-directories t)
      (and (functionp ede-project-directories)
	   (funcall ede-project-directories dir))
      ;; If `ede-project-directories' is a list, maybe add it.
      (when (listp ede-project-directories)
	(dolist (x ede-project-directories)
	  (when (file-exists-p (concat x "/project.el"))
	    (message x)
	    (stm32-load-project x))))))

(defun stm32-open-cubemx ()
  "Open current project in cubeMX or just start application."
  (interactive)
  (let* ((p (ignore-errors(stm32-get-project-root-dir)))
	 (c stm32-cubemx))
    (if p
	(let* ((n (stm32-get-project-name))
	       (f (concat p n ".ioc")))
	  (if (file-exists-p f)
	      (async-shell-command (concat c " " f))
	    (async-shell-command c)))
      (async-shell-command c))))

(provide 'stm32)

(defun stm32-flash-to-mcu()
  "Upload compiled binary to stm32 through gdb"
  (interactive)
  (let ((p (get-buffer-process "*st-util*")))
    (when (not p)
      (stm32-start-gdb))
    (gdb-io-interrupt)
    (gud-basic-call "load")
    (gud-basic-call "cont")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; stm32.el ends here
