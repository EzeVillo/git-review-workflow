using Xunit;

namespace GitReview.Domain.Tests;

/// <summary>
/// Locks the English copy that has to stay byte-aligned with the VS Code extension
/// and the JetBrains plugin. Port of the jetbrains UserCopyTest.
/// </summary>
public class UserCopyTests
{
    [Fact]
    public void Abort_confirm_matches_the_other_clients()
    {
        Assert.Equal("Cancel the review of feature/x?", UserCopy.AbortTitle("feature/x"));
        Assert.Equal(
            "This returns to the branch you started the review from; your uncommitted edits will be discarded.",
            UserCopy.AbortDetail);
        Assert.Equal("Cancel Review", UserCopy.AbortButton);
    }

    [Fact]
    public void Save_confirm_matches_the_other_clients()
    {
        Assert.Equal("Save the review of feature/x for later?", UserCopy.SaveTitle("feature/x"));
        Assert.Equal("Save for Later", UserCopy.SaveButton);
        Assert.Contains("your edits are kept and you can resume later", UserCopy.SaveDetail);
    }

    [Fact]
    public void Continue_confirm_matches_the_other_clients()
    {
        Assert.Equal("Continue the saved review of feature/x?", UserCopy.ContinueTitle("feature/x"));
        Assert.Equal(
            "This switches to review/feature/x and restores your edits in the working tree.",
            UserCopy.ContinueDetail("feature/x"));
        Assert.Equal("Continue", UserCopy.ContinueButton);
    }

    /// <summary>
    /// El caso normal NO notifica: el panel entra en finish-pending y su banner
    /// dice lo mismo con mas contexto -- el destino, que hay que commitear desde
    /// Source Control, y los dos botones --. El toast era esa frase otra vez, un
    /// segundo antes. Queda el residual, que no tiene banner que lo diga.
    /// </summary>
    [Fact]
    public void Finish_only_toasts_when_the_panel_has_no_banner_to_say_it()
    {
        Assert.Null(UserCopy.FinishSuccess("review-fixes/feature/x", FinishOutcome.Pending));
        Assert.Equal(
            "feature/x is ready.",
            UserCopy.FinishSuccess("feature/x", FinishOutcome.NoEdits));
    }

    /// <summary>
    /// Where the edits went, in one place: --onto-source stages them on the branch
    /// itself, everything else on review-fixes/.
    /// </summary>
    [Fact]
    public void Finish_destination_follows_onto_source()
    {
        Assert.Equal("review-fixes/a", UserCopy.FinishDestination(false, "a"));
        Assert.Equal("a", UserCopy.FinishDestination(true, "a"));
    }

    [Fact]
    public void Undo_force_gate_copy_matches_the_other_clients()
    {
        Assert.Equal("Undo this finish?", UserCopy.UndoTitle);
        Assert.Equal("Discard Work and Undo", UserCopy.UndoForceButton);
        Assert.Contains("cannot be undone", UserCopy.UndoForceDetail);
        Assert.Contains("permanently discards", UserCopy.UndoForceDetail);
        // The two undo details are not interchangeable: one restores, one discards.
        Assert.NotEqual(UserCopy.UndoDetailPending, UserCopy.UndoDetailConflict);
    }

    /// <summary>
    /// El asistente ya no confirma: `start` se niega solo con el arbol sucio y
    /// una review empezada se cancela con un boton del panel, asi que la quinta
    /// pantalla solo repetia las cuatro respuestas y agregaba el comando.
    /// Lo que sobrevive de ella es la frase, mudada al paso que ahora ejecuta.
    /// </summary>
    [Fact]
    public void The_last_wizard_step_names_the_branch_it_is_about_to_review()
    {
        Assert.Equal(
            "Start reviewing feature/x — how do you want to read it?",
            UserCopy.StartLayoutTitle("feature/x"));
        // Vale para los DOS caminos que llegan al start -- el asistente y el
        // boton de una fila del bloque de borradores --, asi que no queda
        // ninguna variante sin rama.
        Assert.Contains("x", UserCopy.StartLayoutTitle("x"), StringComparison.Ordinal);
    }

    /// <summary>
    /// Hay UN solo aviso de estado obsoleto, no uno por accion.
    /// <para>
    /// Eran diez, y cada uno nombraba el verbo que no corrio -- "nothing was
    /// saved", "nothing was undone". Ese verbo no es informacion: es el boton
    /// que el revisor acaba de apretar. Lo que si necesita saber es por que no
    /// paso nada, y eso es identico en los diez casos.
    /// </para>
    /// <para>
    /// El test afirma el texto entero a proposito: es copy compartida byte a
    /// byte con userCopy.ts y UserCopy.kt, asi que una divergencia tiene que
    /// romper aca y no en la lectura de alguien.
    /// </para>
    /// </summary>
    [Fact]
    public void Stale_is_one_message_that_says_why_nothing_happened()
    {
        Assert.Equal(
            "The repository changed while you were deciding, so nothing happened.",
            UserCopy.Stale);

        // No nombra ningun verbo del producto: eso es lo que lo hace servir para
        // los ocho comandos, y lo que se rompe si alguien lo vuelve a especializar.
        foreach (var verb in new[] { "finish", "save", "undo", "start", "cancel", "resume", "discard" })
            Assert.DoesNotContain(verb, UserCopy.Stale, StringComparison.Ordinal);
    }

    /// <summary>
    /// Estos mensajes son lo UNICO que llega cuando la CLI muere sin stderr
    /// (matada, rota, un exit != 0 mudo), y decian el argv que no anduvo: "git
    /// review finish --abort --force failed." nombra un comando que quien usa el
    /// panel no escribio, en el unico momento en que no hay nada mas que leer.
    /// Con stderr no cambia nada -- ese texto se sigue mostrando tal cual.
    /// </summary>
    [Fact]
    public void Failure_fallbacks_name_what_did_not_happen()
    {
        Assert.Equal("Could not cancel the review.", UserCopy.FailureFallback("abortReview"));
        Assert.Equal(
            "Could not undo the finish, even discarding the newer work.",
            UserCopy.FailureFallback("undoFinish", new ActionParams.UndoFinish(true)));
        Assert.Equal(
            "Could not undo the finish.",
            UserCopy.FailureFallback("undoFinish", new ActionParams.UndoFinish(false)));
        Assert.Equal(
            "Could not replace the walkthrough.",
            UserCopy.FailureFallback("walkthroughInit", new ActionParams.WalkthroughInit(true)));
        Assert.Equal("Could not move to the next entry.", UserCopy.FailureFallback("next"));
        Assert.Equal("Could not save the setting.", UserCopy.FailureFallback("setBase"));
    }

    /// <summary>The housekeeping fallback still follows the verb that ran.</summary>
    [Fact]
    public void The_housekeeping_fallback_follows_the_verb()
    {
        Assert.Equal(
            "Could not clean up.",
            UserCopy.FailureFallback("cleanReview",
                new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.CleanAll))));
        Assert.Equal(
            "Could not forget that.",
            UserCopy.FailureFallback("forgetReview",
                new ActionParams.Housekeeping(new HousekeepingAction(HousekeepingKind.ForgetSavedAll))));
    }

    /// <summary>Every product action has a message; none of them falls through to a blank.</summary>
    [Fact]
    public void Every_action_has_a_failure_message()
    {
        foreach (var action in ActionArgvMap.ProductActions)
        {
            var message = UserCopy.FailureFallback(action);
            Assert.False(string.IsNullOrWhiteSpace(message), $"{action} has no failure message");
            // Ninguno vuelve a nombrar un comando: eso es lo que se acaba de
            // sacar, y es lo que un mapa nuevo reintroduce sin querer.
            Assert.DoesNotContain("git review", message, StringComparison.Ordinal);
            Assert.EndsWith(".", message);
        }
    }

    [Fact]
    public void The_busy_message_is_the_locks_own()
    {
        Assert.Equal("Another operation is already in progress", UserCopy.DiscardBusy);
        Assert.Equal(MutationLock.DiscardReason, UserCopy.DiscardBusy);
    }

    [Fact]
    public void Picker_empty_state_messages_match_the_other_clients()
    {
        Assert.Equal("No branches to pick a base from were found.", UserCopy.NoBranchesForBase);
        Assert.Equal("No remotes to pick from were found.", UserCopy.NoRemotes);
        Assert.Equal("No active review to preview.", UserCopy.NoActivePreview);
        Assert.Equal(
            "This is a read-only compare review; there is nothing to finish. Use Cancel when done.",
            UserCopy.ReadonlyFinish);
        Assert.Equal("Need a single git repository root.", UserCopy.NoSoleRoot);
    }

    // --- draft wait notice (011) ----------------------------------------------

    [Fact]
    public void Wait_message_asks_to_fill_the_draft_when_it_is_on_screen()
    {
        Assert.Equal(
            "Fill in the reading order for feature/x, then continue.",
            UserCopy.DraftWaitMessage("feature/x", null, null));
        Assert.Equal(
            "The draft is not valid yet: no entries found",
            UserCopy.DraftWaitMessage("feature/x", "no entries found", null));
    }

    /// <summary>
    /// The real case: the open project is a subfolder of the repo, cwd/.git does not
    /// exist, the draft was written anyway and its path only goes out on the CLI's
    /// stdout, which no client shows.
    /// </summary>
    [Fact]
    public void Wait_message_says_where_the_draft_is_when_it_could_not_be_opened()
    {
        Assert.Equal(
            "Fill in the reading order for feature/x, then continue. It could not be opened here" +
            " — the draft is at /repo/.git/review-walkthrough/feature/x.md.",
            UserCopy.DraftWaitMessage("feature/x", null, new UnopenedDraft("/repo/.git/review-walkthrough/feature/x.md")));
        Assert.Equal(
            "The draft is not valid yet: no entries found It could not be opened here" +
            " — the draft is at /repo/.git/review-walkthrough/feature/x.md.",
            UserCopy.DraftWaitMessage("feature/x", "no entries found", new UnopenedDraft("/repo/.git/review-walkthrough/feature/x.md")));
    }

    [Fact]
    public void Wait_message_names_the_relative_file_when_the_path_could_not_be_built()
    {
        Assert.Equal(
            "Fill in the reading order for feature/x, then continue. It could not be opened here" +
            " — look for review-walkthrough/feature/x.md inside this repository's git directory.",
            UserCopy.DraftWaitMessage("feature/x", null, new UnopenedDraft(null)));
    }

    [Fact]
    public void Draft_progress_says_which_half_of_the_loop_is_running()
    {
        Assert.Equal("Drafting a walkthrough for feature/x…", UserCopy.DraftProgress("feature/x", false));
        Assert.Equal("Validating your draft for feature/x…", UserCopy.DraftProgress("feature/x", true));
        Assert.NotEqual(UserCopy.DraftFailed, UserCopy.DraftBuildFailed);
    }

    [Fact]
    public void Compare_confirm_says_it_creates_a_read_only_review()
    {
        var title = UserCopy.CompareConfirmTitle("a", "b", ReviewLayout.Step);
        Assert.Equal(
            "Compare a..b commit by commit? This creates a read-only review (finish will refuse).",
            title);
        Assert.Equal("Comparing a..b…", UserCopy.ComparingProgress("a", "b"));
    }

    [Fact]
    public void The_agent_prompt_is_the_canonical_text_with_this_rows_path()
    {
        Assert.Equal(
            "Fill in the reading order at /repo/.git/review-walkthrough/feature/x.md. " +
            "The instructions are inside the file, in the comment at the top. " +
            "Do not change the file list or the numbering rules.",
            UserCopy.DraftAgentPrompt("/repo/.git/review-walkthrough/feature/x.md"));
    }

    [Fact]
    public void The_agent_prompt_names_no_model_service_or_assistant()
    {
        var text = UserCopy.DraftAgentPrompt("/x.md").ToLowerInvariant();
        foreach (var word in new[] { "copilot", "openai", "claude", "chatgpt", "http" })
            Assert.DoesNotContain(word, text);
    }
}
