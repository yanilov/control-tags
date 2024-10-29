# This file is used by charmbracelet/vhs to generate a screen recoding for the bucket approval demo

Output bucket_approval.gif
Output bucket_approval.mp4

Set WindowBar Colorful

Require tmux
Require assume
Require tagctl
Require jq
Require cat
Require echo


Env AWS_PAGER ""

Hide
  #setup tmux
  Type "tmux -f /dev/null -L test new-session -- zsh" Enter
  Type "tmux split-window -d -h -- zsh && \" Enter
  Type "tmux set status && \" Enter
  Type 'tmux setw pane-border-style "fg=0" && \' Enter
  Type 'tmux setw pane-active-border-style "fg=0"' Enter

  #sso login alice
  Type "assume alice:control-tags-test-account-1/AdministratorAccess" Enter

  Sleep 0.5
  Ctrl+B
  Type o
  Sleep 1
  Ctrl+L
  Sleep 0.5

  #sso login bob
  Type "assume bob:control-tags-test-account-1/AdministratorAccess" Enter

  Sleep 0.5
  Ctrl+B
  Type o
  Sleep 1
  Ctrl+L
  Sleep 0.5
Show

#initial delay for the purpose of flow in the demo
Sleep 1

#broadcast on
Hide
  Ctrl+B
  Type ':'
  Type setw synchronize-panes on Enter
  # no autosuggestiions
  Type 'export ZSH_AUTOSUGGEST_HISTORY_IGNORE="*"' Enter
  # source the iam assume functions
  Type 'source ~/site-functions/iam.sh' Enter
  # assume the mirror role
  Type "tagctl mirror assume | iam.become" Enter
  Sleep 2
  Ctrl+L
  Sleep 1.5
Show

# show identities
Type "aws sts get-caller-identity | jq -r '.Arn' | cut -d '/' -f3" Enter
Sleep 2


#broadcast off
Hide
  Ctrl+B
  Type ':'
  Type 'setw synchronize-panes off' Enter
Show

Sleep 1

# alice can't delete a bucket
Type "aws s3 ls" Enter
Sleep 2
Type "aws s3api delete-bucket --bucket deletemeifyoucan" Enter
Sleep 3

# bob grants alice an approval
Ctrl+B
Type o
Type "tagctl ticket set tester.alice" Enter
Sleep 2
Ctrl+B
Type o

# blindly wait for SCP to update
Sleep 3

# alice has a ticket
Type "tagctl ticket get" Enter
Sleep 2

# alice can delete a bucket
Type "aws s3api delete-bucket --bucket deletemeifyoucan" Enter
Sleep 2
Type "aws s3 ls" Enter
Sleep 3
