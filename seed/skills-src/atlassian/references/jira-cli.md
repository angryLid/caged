## Usage
The tool currently comes with an issue, epic, and sprint explorer. The flags are [POSIX-compliant](https://www.gnu.org/software/libc/manual/html_node/Argument-Syntax.html).
You can combine available flags in any order to create a unique query. For example, the command below will give you high priority issues created this month
with status `To Do` that are assigned to you and has the label `backend`.
```sh
jira issue list -yHigh -s"To Do" --created month -lbackend -a$(jira me)
```

## Commands
### Issue
Issues are displayed in an interactive table view by default. You can output the results in a plain view using the `--plain` flag.

#### List
The `list` command lets you search and navigate the issues. The issues are sorted by `created` field in descending order by default.

```sh
# List recent issues
$ jira issue list

# List issues created in last 7 days
$ jira issue list --created -7d

# List issues in status "To Do"
$ jira issue list -s"To Do"

# List recent issues in plain mode
$ jira issue list --plain

# List recent issues in raw JSON format
$ jira issue list --raw

# List recent issues in csv format
$ jira issue list --csv

# List issue in the same order as you see in the UI
$ jira issue list --order-by rank --reverse

# You can execute raw JQL within a given project context using `--jql/-q` option.
# For instance, the following command will list issues in the current project whose
# summary has a word cli.
$ jira issue list -q "summary ~ cli"
```

Check some more examples/use-cases below.

<details><summary>List issues that I am watching</summary>

```sh
jira issue list -w
```
</details>

<details><summary>List issues assigned to me</summary>

```sh
jira issue list -a$(jira me)
```
</details>

<details><summary>List issues assigned to a user and are reported by another user</summary>

```sh
jira issue list -a"User A" -r"User B"
```
</details>

<details><summary>List issues assigned to me, is of high priority and is open</summary>

```sh
jira issue list -a$(jira me) -yHigh -sopen
```
</details>

<details><summary>List issues assigned to no one and are created this week</summary>

```sh
jira issue list -ax --created week
```
</details>

<details><summary>List issues with resolution won't do</summary>

```sh
jira issue list -R"Won't do"
```
</details>

<details><summary>List issues whose status is not done and is created before 6 months and is assigned to someone</summary>

```sh
# Tilde (~) acts as a not operator
jira issue list -s~Done --created-before -24w -a~x
```
</details>

<details><summary>List issues created within an hour and updated in the last 30 minutes :stopwatch:</summary>

```sh
jira issue list --created -1h --updated -30m
```
</details>

<details><summary>Give me issues that are of high priority, are in progress, were created this month, and have given labels :fire:</summary>

```sh
jira issue list -yHigh -s"In Progress" --created month -lbackend -l"high-prio"
```
</details>

<details><summary>Wait, what was that ticket I opened earlier today? :tired_face:</summary>

 ```sh
 jira issue list --history
 ```
</details>

<details><summary>What was the first issue I ever reported on the current board? :thinking:</summary>

```sh
jira issue list -r$(jira me) --reverse
```
</details>

<details><summary>What was the first bug I ever fixed in the current board? :beetle:</summary>

```sh
jira issue list -a$(jira me) -tBug -sDone -rFixed --reverse
```
</details>

<details><summary>What issues did I report this week? :man_shrugging:</summary>

```sh
jira issue list -r$(jira me) --created week
```
</details>

<details><summary>Am I watching any tickets in project XYZ? :monocle_face:</summary>

```sh
jira issue list -w -pXYZ
```
</details>

#### Create
The `create` command lets you create an issue.

```sh
# Create an issue using an interactive prompt
$ jira issue create

# Pass required parameters and use --no-input option to skip prompt
$ jira issue create -tBug -s"New Bug" -yHigh -lbug -lurgent -b"Bug description" --fix-version v2.0 --no-input
```

To attach epic to an issue on creation, you can use `-P/--parent` field. We call it parent because the semantics of epic
has been changed in `next-gen` project.

```sh
# Create an issue of type Story and attach it to epic with key EPIC-42
$  jira issue create -tStory -s"Epic during creation" -PEPIC-42
```

You can use a `--custom` flag to set custom fields while creating the issue. See [this post](https://github.com/ankitpokhrel/jira-cli/discussions/346) for more details.

The command supports both [GitHub-flavored](https://github.github.com/gfm/)
and [Jira-flavored](https://jira.atlassian.com/secure/WikiRendererHelpAction.jspa?section=all) Markdown for writing
description. You can load pre-defined templates using `--template` flag.

```sh
# Load description from template file
$ jira issue create --template /path/to/template.tmpl

# Get description from standard input
$ jira issue create --template -

# Or, use pipe to read input directly from standard input
$ echo "Description from stdin" | jira issue create -s"Summary" -tTask
```

#### Edit
The `edit` command lets you edit an issue.

```sh
$ jira issue edit ISSUE-1

# Edit issue in the configured project
$ jira issue edit ISSUE-1 -s"New Bug" -yHigh -lbug -lurgent -CBackend -b"Bug description"

# Use --no-input option to disable interactive prompt
$ jira issue edit ISSUE-1 -s"New updated summary" --no-input

# Use minus (-) to remove label, component or fixVersion
# For instance, to edit issue to
#   - remove label p2, component FE, fixVersion v1.0
#   - add label p1, component BE, fixVersion v2.0
$ jira issue edit ISSUE-1 --label -p2 --label p1 --component -FE --component BE --fix-version -v1.0 --fix-version v2.0
```

#### Assign
The `assign` command lets you assign a user to an issue.

```sh
# Assign user to an issue using an interactive prompt
$ jira issue assign

# Pass required parameters to skip prompt
$ jira issue assign ISSUE-1 "Jon Doe"

# Assign to self
$ jira issue assign ISSUE-1 $(jira me)

# Will prompt for selection if keyword suffix returns multiple entries
$ jira issue assign ISSUE-1 suffix

# Assign to default assignee
$ jira issue assign ISSUE-1 default

# Unassign
$ jira issue assign ISSUE-1 x
```

#### Move/Transition
The `move` command lets you transition an issue from one state to another.

```sh
# Move an issue using an interactive prompt
$ jira issue move

# Pass required parameters to skip prompt
$ jira issue move ISSUE-1 "In Progress"
```

If your workflow allows to add comment, resolution or assignee while moving an issue, you can do so as shown below.
See [this documentation](https://confluence.atlassian.com/jirakb/how-to-add-a-comment-during-a-transition-779160682.html) on how to setup your workflow to allow these fields.

```sh
# Move an issue and add comment
$ jira issue move ISSUE-1 "In Progress" --comment "Started working on it"

# Set resolution to fixed and assign to self while moving the issue
$ jira issue move ISSUE-1 Done -RFixed -a$(jira me)
```

To transition the selected issue from the TUI, press `m`.

#### View
The `view` command lets you see issue details in a terminal. Atlassian document is roughly converted to Markdown
and is nicely displayed in the terminal.

The command uses `less` as a pager by default. To set your own pager, see https://github.com/ankitpokhrel/jira-cli/discussions/569.

```sh
$ jira issue view ISSUE-1
```

The view screen will display linked issues and the latest comment after the description. Note that the displayed comment may
not be the latest one if you for some reason have more than 5k comments in a ticket.

```sh
# Show 5 recent comments when viewing the issue
$ jira issue view ISSUE-1 --comments 5
```

#### Link
The `link` command lets you link two issues.

```sh
# Link an issue using an interactive prompt
$ jira issue link

# Pass required parameters to skip prompt
$ jira issue link ISSUE-1 ISSUE-2 Blocks
```

##### Remote
The `remote` command lets you add a remote web link to an issue.

```sh
# Adds a remote web link using an interactive prompt
$ jira issue link remote

# Pass required parameters to skip prompt
$ jira issue link remote ISSUE-1 https://example.com "Example text"
```

#### Unlink
The `unlink` command lets you unlink two linked issues.

```sh
# Unlink issues using interactive prompt
$ jira issue unlink

# Pass required parameters to skip prompt
$ jira issue unlink ISSUE-1 ISSUE-2
```

#### Clone
The `clone` command lets you clone an issue. You can update fields like summary, priority, assignee, labels, and
components when cloning the issue. The command also allows you to replace a part of the string (case-sensitive)
in summary and description using `--replace/-H` option.

```sh
# Clone an issue
$ jira issue clone ISSUE-1

# Clone issue and modify the summary, priority and assignee
$ jira issue clone ISSUE-1 -s"Modified summary" -yHigh -a$(jira me)

# Clone issue and replace text from summary and description
$ jira issue clone ISSUE-1 -H"find me:replace with me"
```

#### Delete
The `delete` command lets you delete an issue.

```sh
# Delete an issue using an interactive prompt
$ jira issue delete

# Pass required parameters to skip prompt
$ jira issue delete ISSUE-1

# Delete task along with all of its subtasks
$ jira issue delete ISSUE-1 --cascade
```

#### Comment
The `comment` command provides a list of sub-commands to manage issue comments.

##### Add
The `add` command lets you add a comment to an issue. The command supports both [GitHub-flavored](https://github.github.com/gfm/)
and [Jira-flavored](https://jira.atlassian.com/secure/WikiRendererHelpAction.jspa?section=all) Markdown for writing
comment. You can load pre-defined templates using `--template` flag.

```sh
# Add a comment using an interactive prompt
$ jira issue comment add

# Pass required parameters to skip prompt
$ jira issue comment add ISSUE-1 "My comment body"

# Same as above but as an internal comment
$ jira issue comment add ISSUE-1 "My comment body" --internal

# Load comment from template file
$ jira issue comment add ISSUE-1 --template /path/to/template.tmpl

# Get comment from standard input
$ jira issue comment add ISSUE-1 --template -

# Or, use pipe to read input directly from standard input
$ echo "Comment from stdin" | jira issue comment add ISSUE-1
```

> [!NOTE]
> For the comment body, the positional argument always takes precedence over the `--template` flag if both of them are passed. In the
example below, the body will be picked from positional argument instead of the template.
```sh
jira issue comment add ISSUE-42 "comment body positional" --template - <<'EOF'
comment body template
EOF
```

#### Worklog
The `worklog` command provides a list of sub-commands to manage issue worklog (timelog).

##### Add
The `add` command lets you add a worklog to an issue. The command supports Markdown for worklog comments.

```sh
# Add a worklog using an interactive prompt
$ jira issue worklog add

# Pass required parameters and use --no-input to skip prompt
$ jira issue worklog add ISSUE-1 "2d 3h 30m" --no-input

# You can add a comment using --comment flag when adding a worklog
$ jira issue worklog add ISSUE-1 "10m" --comment "This is a comment" --no-input
```

### Epic
Epics are displayed in an explorer view by default. You can output the results in a table view using the `--table` flag.
When viewing epic issues, you can use all filters available for the issue command.

See [usage](#navigation) to learn more about UI interaction.

#### List
You can use all flags supported by `issue list` command here except for the issue type.

```sh
# List epics
$ jira epic list

# List epics in a table view
$ jira epic list --table

# List epics reported by me and are open
$ jira epic list -r$(jira me) -sOpen

# List issues in an epic
$ jira epic list KEY-1

# List all issue in an epic KEY-1 that is unassigned and has a high priority
$ jira epic list KEY-1 -ax -yHigh

# List high priority epics
$ jira epic list KEY-1 -yHigh

# List epic issues ordered by rank in ascending order
$ jira epic list KEY-1 --order-by rank --reverse
```

#### Create
Creating an epic is the same as creating the issue except you also need to provide an epic name.

```sh
# Create an issue using an interactive prompt
$ jira epic create

# Pass required parameters to skip prompt or use --no-input flag to skip prompt for non-mandatory params
$ jira epic create -n"Epic epic" -s"Everything" -yHigh -lbug -lurgent -b"Epic description"
```

#### Add
The `add` command allows you to add issues to the epic. You can add up to 50 issues to the epic at once.

```sh
# Add issues to the epic using an interactive prompt
$ jira epic add

# Pass required parameters to skip prompt
$ jira epic add EPIC-KEY ISSUE-1 ISSUE-2
```

#### Remove
The `remove` command allows you to remove issues from the epic. You can remove up to 50 issues from the epic at once.

```sh
# Remove issues to the epic using an interactive prompt
$ jira epic remove

# Pass required parameters to skip prompt
$ jira epic remove ISSUE-1 ISSUE-2
```

### Sprint
Sprints are displayed in an explorer view by default. You can output the results in a table view using the `--table` flag.
When viewing sprint issues, you can use all filters available for the issue command. The tool only shows 25 recent sprints.

See [usage](#navigation) to learn more about UI interaction.

#### List
You can use all flags supported by `issue list` command to filter issues in the sprint.

```sh
# List sprints in an explorer view
$ jira sprint list

# List sprints in a table view
$ jira sprint list --table

# List issues in the current active sprint
$ jira sprint list --current

# List issues in the current active sprint that are assigned to me
$ jira sprint list --current -a$(jira me)

# List issues in the previous sprint
$ jira sprint list --prev

# List issues in next planned sprint
$ jira sprint list --next

# List future and active sprints
$ jira sprint list --state future,active

# List issues in a particular sprint. You can use all flags supported by issue list command here.
# To get sprint id use `jira sprint list` or `jira sprint list --table`
$ jira sprint list SPRINT_ID

# List high priority issues in a sprint are assigned to me
$ jira sprint list SPRINT_ID -yHigh -a$(jira me)

# List sprint issues ordered by rank in ascending order
$ jira sprint list SPRINT_ID --order-by rank --reverse
```

#### Add
The `add` command allows you to add issues to the sprint. You can add up to 50 issues to the sprint at once.

```sh
# Add issues to the sprint using interactive prompt
$ jira sprint add

# Pass required parameters to skip prompt
$ jira sprint add SPRINT_ID ISSUE-1 ISSUE-2
```

### Releases

Interact with releases (project versions).  
Ensure the [feature is enabled](https://support.atlassian.com/jira-software-cloud/docs/enable-releases-and-versions/) on your instance.

#### List

```sh
# List releases for default project
$ jira release list

# List releases for specific project
$ jira release list --project 1000
$ jira release list --project KEY
```

### Other commands

<details><summary>Navigate to the project</summary>

```sh
jira open
```
</details>

<details><summary>Navigate to the issue</summary>

```sh
jira open KEY-1
```
</details>

<details><summary>List all projects you have access to</summary>

```sh
jira project list
```
</details>

<details><summary>List all boards in a project</summary>

```sh
jira board list
```
</details>
