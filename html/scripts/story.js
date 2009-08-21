// Daily Kos story editing system. (c)2006 Kos Media LLC

var kst={MIN_INTRO_CHARS:300,MAX_INTRO_CHARS:1350,MAX_POLL_OPTIONS:15,SUBMIT_BASE:"/ajax/story/",SITE_TITLE:"Daily Kos: ",DRAFT_TITLE_PREFIX:"Daily Kos: Draft: ",DRAFT_INTERVAL:15000,ESCAPE_RAW_CHARS:true,SAVE_DRAFT_MSG:"Save Draft",DRAFT_SAVED_MSG:"Draft Saved",editorContentChanged:function(evt){if(!kst.editorContentChangeTimeout){kst.editorContentChangeTimeout=setTimeout(kst.didEditorContentChange,10);}},didEditorContentChange:function(){kst.editorContentChangeTimeout=null;var ieText=$("ieText");var beText=$("beText");if(ieText.kosValue!=ieText.value||beText.kosValue!=ieText.value){log("story editor content has changed");ieText.ondrop=ieText.onkeypress=null;beText.ondrop=beText.onkeypress=null;$("iePButton").disabled=false;$("bePButton").disabled=false;var intro=kst.introDiv;var extended=$("extended");extended.disabled=intro.disabled=true;if(kos.isIE6Minus){extended.style.filter=intro.style.filter="alpha(opacity=40)";}
extended.style.opacity=intro.style.opacity=0.4;var draftButton=$("draftButton");if(draftButton&&(kst.authorId==kos.uid||kst.inq)){draftButton.disabled=false;draftButton.value=kst.SAVE_DRAFT_MSG;}
kst.startDraftTimeout();}
return true;},prepareForPublication:function(evt){var ieText=$("ieText");if(!ieText){return false;}
var editorErrorMessage=$("ieErrorMessage");var textiledIntroValue=kos.textile(ieText.value);textiledIntroValue=kos.maxString(textiledIntroValue);textiledIntroValue=textiledIntroValue.replace(/(<a href)/gi,'<a target="_blank" href');var beText=$("beText");var textiledBodyValue=kos.textile(beText.value);textiledBodyValue=kos.maxString(textiledBodyValue);textiledBodyValue=textiledBodyValue.replace(/(<a href)/gi,'<a target="_blank" href');var intro=kst.introDiv;var extended=$("extended");extended.disabled=intro.disabled=false;if(kos.isIE6Minus){extended.style.filter=intro.style.filter="alpha(opacity=100)";}
extended.style.opacity=intro.style.opacity=1;intro.innerHTML=textiledIntroValue;extended.innerHTML=textiledBodyValue;if(kos.isModifiedClick(evt)&&(!this.id||this.id!="previewButton")){log("quick preview");ieText.kosValue=ieText.value;ieText.ondrop=ieText.onkeypress=kst.editorContentChanged;beText.kosValue=beText.value;beText.ondrop=beText.onkeypress=kst.editorContentChanged;$("iePButton").disabled=true;$("bePButton").disabled=true;if(this.id.charAt(0)=='i'){var ypos=kos.getPosY(kst.introDiv);}else{ypos=kos.getPosY($("extended"));}
window.scrollTo(0,ypos-12);kst.submitDraft("preview");return false;}
var titleInput=$("titleInput");var titleSpan=kos.getElementByClassName(kst.entryDiv,"diaryTitle","span");var titleErrorMessage=$("titleErrorMessage");var titleText=kos.makeHighBitHtmlEntities(titleInput.value);titleText=kos.titleClean(titleText);document.title=kst.DRAFT_TITLE_PREFIX+titleText;if(titleText=="untitled diary"||!(titleText.length>0)){var onComplete=kos.selectThis.bind(titleInput);kos.setDisplayStyle(titleErrorMessage,kos.DISPLAY_BLOCK,null,true,50,onComplete);return false;}
titleErrorMessage.style.display=kos.DISPLAY_NONE;var diaryDraftsUl=$("diaryDrafts");if(diaryDraftsUl){var storySid=kos.STORY_BASE+kos.sid;var diaryDrafts=kos.getChildrenByTagName(diaryDraftsUl,"li");for(var d=0;d<diaryDrafts.length;++d){var draftA=kos.getChildByTagName(diaryDrafts[d],"a");if(draftA){var draftHref=draftA.getAttribute("href");if(!draftHref){draftHref=draftA.href;}
if(draftHref&&(draftHref.length>storySid.length)){draftHref=draftHref.substring(draftHref.length-storySid.length);}
if(draftHref==storySid){log("updated draft title in menu");draftA.innerHTML=titleText;break;}}}}
if(textiledIntroValue.length>kst.MAX_INTRO_CHARS||(textiledBodyValue.length<1&&textiledIntroValue.length<kst.MIN_INTRO_CHARS)||(textiledBodyValue.length>0&&textiledIntroValue.length<1)){onComplete=kos.selectThis.bind(ieText);kos.setDisplayStyle(editorErrorMessage,kos.DISPLAY_BLOCK,null,true,20,onComplete);return false;}
editorErrorMessage.style.display=kos.DISPLAY_NONE;var tagErrorMessage=$("tagErrorMessage");var tagInput=$("tagInput");if(!(tagInput.value.length>0)){kst.editTags();onComplete=kos.selectThis.bind(tagInput);kos.setDisplayStyle(tagErrorMessage,kos.DISPLAY_BLOCK,null,true,50,onComplete);return false;}
tagErrorMessage.style.display=kos.DISPLAY_NONE;var pollErrorMessage=$("pollErrorMessage");var hasPoll=false;var pollForm=kos.getChildByTagName(kst.pollDiv,"form");log("kst.pollDiv: ",kst.pollDiv);log("pollForm: ",pollForm);if(pollForm){var pollQueryInput=$("piq");if(pollQueryInput){for(var i=1;i<=kst.MAX_POLL_OPTIONS;++i){var pin=$("pi"+i);if(pin&&pin.value.length>0){hasPoll=true;var pLabel=kos.getChildByTagName(pin.parentNode,"label");if(pLabel){pLabel.innerHTML=kos.titleClean(pin.value);}}}
log("hasPoll: ",hasPoll);if(hasPoll){if(pollQueryInput.value.length<1){onComplete=kos.selectThis.bind(pollQueryInput);kos.setDisplayStyle(pollErrorMessage,kos.DISPLAY_BLOCK,null,true,50,onComplete);return false;}
for(i=1;i<=kst.MAX_POLL_OPTIONS;++i){pin=$("pi"+i);if(pin&&pin.value.length<1){pin.parentNode.parentNode.style.display=kos.DISPLAY_NONE;var prn=$("pr"+i+"_"+kst.pollDiv.id);if(prn){prn.style.display=kos.DISPLAY_NONE;}}}
kos.getElementByClassName(kst.pollDiv,"pollQuery","p").innerHTML=kos.titleClean(pollQueryInput.value);pollForm.className="vote";}}else{hasPoll=true;}}
if(!hasPoll){kst.pollDiv.style.display=kos.DISPLAY_NONE;}
if(pollErrorMessage){pollErrorMessage.style.display=kos.DISPLAY_NONE;}
titleSpan.innerHTML=titleText;kos.makeNewTags();kst.stopEditingTags();return true;},previewDiary:function(evt){if(!kst.prepareForPublication(evt)){return false;}
kos.mainDiv.className="previewing";window.scrollTo(0,kos.getPosY(kos.mainDiv)+130);kst.submitDraft("preview");return false;},editDiary:function(){kst.setupForEditing();kos.mainDiv.className="editing";$("ieText").focus();window.scrollTo(0,kos.getPosY(kos.mainDiv)+130);return false;},setupForEditing:function(){var ie=$("ie");if(!ie){return false;}
var intro=kst.introDiv;var extended=$("extended");var ieText=$("ieText");var beText=$("beText");ieText.kosValue=ieText.value;ieText.ondrop=ieText.onkeypress=kst.editorContentChanged;beText.kosValue=beText.value;beText.ondrop=beText.onkeypress=kst.editorContentChanged;$("iePButton").disabled=false;$("bePButton").disabled=false;kst.editTags();var pollForm=kos.getChildByTagName(kst.pollDiv,"form");var piq=$("piq");if(pollForm&&piq){for(var i=1;i<=kst.MAX_POLL_OPTIONS;++i){var pin=$("pi"+i);if(pin){pin.parentNode.parentNode.style.display=kos.DISPLAY_BLOCK;}
var prn=$("pr"+i+"_"+kst.pollDiv.id);if(prn){prn.style.display=kos.DISPLAY_BLOCK;}}
if(piq&&piq.value.length>0){pollForm.className="voteform";}else{pollForm.className="add";}
kst.pollDiv.style.display=kos.DISPLAY_BLOCK;}
var draftButton=$("draftButton");if(draftButton&&(kst.authorId==kos.uid||kst.inq)){draftButton.disabled=false;draftButton.value=kst.SAVE_DRAFT_MSG;}
return true;},addPoll:function(){var pollForm=kos.getChildByTagName(kst.pollDiv,"form");var piq=$("piq");if(pollForm&&piq){pollForm.className="voteform";piq.focus();piq.select();}
return false;},removePoll:function(){var pollForm=kos.getChildByTagName(kst.pollDiv,"form");if(pollForm){pollForm.className="add";var addPoll=$("addPoll");if(addPoll){addPoll.focus();}
var piq=$("piq");if(piq){for(var i=1;i<=kst.MAX_POLL_OPTIONS;++i){var pin=$("pi"+i);if(pin){pin.value="";}}
piq.value="";var pollQueryP=kos.getElementByClassName(kst.pollDiv,"pollQuery","p");if(pollQueryP){pollQueryP.innerHTML="";}}}
return false;},stopEditingTags:function(){var tagSubmit=$("tagSubmit");if(tagSubmit){tagSubmit.disabled=false;tagSubmit.style.display=kos.DISPLAY_INLINE;}
$("tagEditor").style.display=kos.DISPLAY_NONE;},editTags:function(){var tagSubmit=$("tagSubmit");if(tagSubmit){tagSubmit.style.display=kos.DISPLAY_NONE;tagSubmit.disabled=true;}
kos.editTags(null,true);},confirmDelete:function(){var doDelete=false;if(!kos.isIE&&(kst.hasBeenPublished||kos.getCommentCount()>5)){var answer=prompt(document.title+":\nAre you certain you want to delete this diary? All text and all comments will be irretreivably lost."+"\n\nIf you wish to delete, you must type \"delete\" in the box below and press OK.","");if(answer=="delete"){doDelete=true;}}else{doDelete=confirm(document.title+":\nAre you certain you want to delete this diary? All text and all comments will be irretreivably lost.");}
if(doDelete){this.disabled=true;var bbs=kos.createBusyBallSpan("Deleting...");kos.insertAfter(bbs,this.parentNode.lastChild);kos.addBusyBall(bbs);var bag={input:this,bbs:bbs};var params="sid="+kos.sid;var kjaxreq=new kos.kjax(kst.finishDelete,bag,kst.SUBMIT_BASE+"delete",params,"POST");}
return false;},finishDelete:function(kjaxReq){this.input.disabled=false;if(kjaxReq.FAILED){kos.removeBusyBall(this.bbs,false);return false;}
kos.removeBusyBall(this.bbs,true);alert(document.title+":\nThis Diary has been deleted. You will now be redirected to the front page.");document.location.replace(kos.URL_BASE);return true;},storyUpdated:function(){if(kst.submittedUpdate){kst.submittedUpdate=false;}else{var isEditingStory=false;if(kos.mainDiv.className.indexOf("ing")>-1){isEditingStory=true;}
if(isEditingStory||(kos.commentEditor&&(kos.commentEditor.style.display==kos.DISPLAY_BLOCK))){log("Version collision detected! Alert shown.");alert(document.title+":\nIt appears this diary has been updated by an admin or yourself from another window. "+"If you submit changes to this diary now, you might overwrite those changes. "+"Please save your edits to a text file on your computer, reload this page manually "+"to get the latest version, and re-submit your edits.");return false;}else{log("Version collision detected! Reloading page.");kos.loadStoryWithComments();return true;}}
return true;},saveAsDraft:function(){kst.submitDraft("manual");return false;},startDraftTimeout:function(){var kosInsistsOnThisDesign=kst.hasBeenPublished;if(!kst.draftTimeout&&kst.DRAFT_INTERVAL>0&&kst.authorId==kos.uid&&!kosInsistsOnThisDesign){log("starting draft timeout...");kst.draftTimeout=setTimeout(kst.submitDraft,kst.DRAFT_INTERVAL);}},submitDraft:function(mode){var kosInsistsOnThisDesign=kst.hasBeenPublished;if(mode=="preview"&&kosInsistsOnThisDesign){log("draft not saved for preview because of client specification");return false;}
if(mode=="preview"&&kst.authorId!=kos.uid&&!kst.inq){log("draft not saved for preview because user not author");return false;}
log("submitting draft...mode: "+mode);if(kst.draftTimeout){clearTimeout(kst.draftTimeout);kst.draftTimeout=null;}
var draftop=(mode=="preview")?"draft/prev":"draft";
var boundaryString="AaB03x";var data=kst.encodeDiary(boundaryString,true);var kjaxreq=new kos.kjax(kst.finishSubmitDraft,null,kst.SUBMIT_BASE+draftop,data,"POST","multipart/form-data; boundary="+boundaryString);if(false&&mode!="preview"){log("draft not from preview, restarting timeout");kst.startDraftTimeout();}
return false;},movQueue:function(){/* if(!kst.queueable&&!kst.inq){return false;} */if(kst.draftTimeout){clearTimeout(kst.draftTimeout);kst.draftTimeout = null;}var boundaryString = "AaB03x";var data = kst.encodeDiary(boundaryString, true);var kjaxreq = new kos.kjax(kst.finishSubmitDraft, null, kst.SUBMIT_BASE + "movq", data, "POST", "multipart/form-data; boundary=" + boundaryString);$("movQueueButton").value=(kst.queueable)?"Remove From Queue":"Move To Queue";kst.queueable=!kst.queueable;kst.inq=!kst.inq;if($("inEditQ")){if(kst.inq){$("inEditQ").style.display=kos.DISPLAY_INLINE;}else{$("inEditQ").style.display=kos.DISPLAY_NONE;}}kst.submittedUpdate=true;return false;},finishSubmitDraft:function(kjaxReq){if(!kjaxReq.FAILED){var errMsg=kjaxReq.xhr.responseText;if(errMsg.indexOf("nosid")!=-1){log("nosid error.");alert("Unfortunately your diary entry has become corrupted somehow."+"\nPlease copy and save your text onto files on your computer, and create a New Diary Entry."+"\nPlease delete this diary draft afterward.");return;}
var introErrors=$("introErrors");if(introErrors){introErrors.parentNode.removeChild(introErrors);}
var bodyErrors=$("bodyErrors");if(bodyErrors){bodyErrors.parentNode.removeChild(bodyErrors);}
if (errMsg.indexOf("error") > -1){
kos.mainDiv.className = "editing";
var introErrorsText=kst.parseErrorReport(errMsg,"introErrors");var ieErrorMessage=$("ieErrorMessage");if(introErrorsText&&ieErrorMessage){introErrors=$("introErrors");if(!introErrors){introErrors=document.createElement("div");introErrors.id="introErrors";}
introErrors.innerHTML=introErrorsText;kos.insertAfter(introErrors,ieErrorMessage);kos.setDisplayStyle($("introErrors"),kos.DISPLAY_BLOCK,null,true);$("ieText").focus();}
var bodyErrorsText=kst.parseErrorReport(errMsg,"bodyErrors");var beText=$("beText");if(bodyErrorsText&&beText){bodyErrors=$("bodyErrors");if(!bodyErrors){bodyErrors=document.createElement("div");bodyErrors.id="bodyErrors";}
bodyErrors.innerHTML=bodyErrorsText;log("There are bodyErrors");beText.parentNode.parentNode.insertBefore(bodyErrors,beText.parentNode);kos.setDisplayStyle($("bodyErrors"),kos.DISPLAY_BLOCK,null,true);beText.focus();}
}
log("draft submission succeeded.");if(kst.publishPending){kst.publishPending=false;log("user not author (or client specified this), now continuing through to publish");kst.doPublishDiary();return;}
var draftButton=$("draftButton");if(draftButton){draftButton.disabled=true;draftButton.value=kst.DRAFT_SAVED_MSG;}
var ieText=$("ieText");var beText=$("beText");if(ieText&&beText){ieText.kosValue=ieText.value;ieText.ondrop=ieText.onkeypress=kst.editorContentChanged;beText.kosValue=beText.value;beText.ondrop=beText.onkeypress=kst.editorContentChanged;}
var diaryDraftsUl=$("diaryDrafts");if(diaryDraftsUl&&typeof kos!="undefined"){var noDraftsP=$("noDiaryDrafts");if(noDraftsP){noDraftsP.style.display=kos.DISPLAY_NONE;}
var titleText=kos.makeHighBitHtmlEntities($("titleInput").value);titleText=kos.titleClean(titleText);document.title=kst.DRAFT_TITLE_PREFIX+titleText;var storySid=kos.STORY_BASE+kos.sid;var diaryDrafts=kos.getChildrenByTagName(diaryDraftsUl,"li");for(var d=0;d<diaryDrafts.length;++d){var draftA=kos.getChildByTagName(diaryDrafts[d],"a");if(draftA){var draftHref=draftA.getAttribute("href");if(!draftHref){draftHref=draftA.href;}
if(draftHref&&(draftHref.length>storySid.length)){draftHref=draftHref.substring(draftHref.length-storySid.length);}
if(draftHref==storySid){log("updated draft menu title");draftA.innerHTML=titleText;draftA.style.display=kos.DISPLAY_BLOCK;return;}}}
var draftLi=document.createElement("li");draftLi.innerHTML='<a href="'+storySid+'">'+titleText+'</a>';diaryDraftsUl.appendChild(draftLi);log("added draft to draft menu");}}else{log("draft submission failed");}},publishDiary:function(evt){var skippingPreview=kos.mainDiv.className.indexOf("previewing")==-1;if(skippingPreview){if(!kst.prepareForPublication(evt)){return false;}}
var kosInsistsOnThisDesign=kst.hasBeenPublished;if(kst.authorId!=kos.uid||skippingPreview||kosInsistsOnThisDesign){kst.publishPending=true;kst.submitDraft("publish");}else{kst.doPublishDiary();}
return false;},doPublishDiary:function(){log("publishing diary...");var boundaryString="AaB03x";var data=kst.encodeDiary(boundaryString,false);this.disabled=true;var bbs=kos.createBusyBallSpan("Publishing...");var publishButton=$("publishButton");var h3=publishButton.parentNode.parentNode;h3.insertBefore(bbs,h3.firstChild);kos.addBusyBall(bbs);var bag={input:publishButton,bbs:bbs};var kjaxreq=new kos.kjax(kst.finishPublish,bag,kst.SUBMIT_BASE+"publish",data,"POST","multipart/form-data; boundary="+boundaryString); if($("movQueueButton")){ var ds=$("displaystatus").value; $("movQueueButton").disabled=(ds >= 0)?true:false; $("movQueueButton").value=(ds >= 0)?"Published":(ds == -5)?"Remove from Queue":"Move to Queue"; if(ds == -5){ $("inEditQ").style.display=kos.DISPLAY_INLINE; kst.inq=true; kst.queueable=false; } else{ $("inEditQ").style.display=kos.DISPLAY_NONE; kst.inq=false; kst.queueable=(ds == -4)?true:false; }}return false;},encodeDiary:function(boundaryString,isDraft){var bs="--"+boundaryString;var rn='\r\n';var fc='\r\nContent-Disposition: form-data; name="';var fe='"\r\n\r\n';var data="";data+=bs+fc+'sid'+fe;data+=kos.sid+rn;data+=bs+fc+'authorid'+fe;data+=kst.authorId+rn;var titleText=kos.makeHighBitHtmlEntities($("titleInput").value);titleText=kos.titleClean(titleText);data+=bs+fc+'title'+fe;data+=titleText+rn;var introraw=$("ieText").value;var bodyraw=$("beText").value;if(isDraft){introraw=kos.maxString(introraw);if(kst.ESCAPE_RAW_CHARS){introraw=kos.makeHighBitHtmlEntities(introraw);}
data+=bs+fc+'introraw'+fe;data+=introraw+rn;bodyraw=kos.maxString(bodyraw);if(kst.ESCAPE_RAW_CHARS){bodyraw=kos.makeHighBitHtmlEntities(bodyraw);}
data+=bs+fc+'bodyraw'+fe;data+=bodyraw+rn;}else{var displaystatus=$("displaystatus");if(displaystatus){data+=bs+fc+'displaystatus'+fe;data+=displaystatus.value+rn;}
var timeupdate=$("timeupdate");if(timeupdate&&timeupdate.checked){data+=bs+fc+'timeupdate'+fe;data+=timeupdate.value+rn;}
var commentStatus=$("comment_status");if(commentStatus){data+=bs+fc+'comment_status'+fe;data+=commentStatus.value+rn;}
var introtext=kos.textile(introraw);introtext=kos.maxString(introtext);data+=bs+fc+'introtext'+fe;data+=introtext+rn;var bodytext=kos.textile(bodyraw);bodytext=kos.maxString(bodytext);data+=bs+fc+'bodytext'+fe;data+=bodytext+rn;}
var tagText=kos.getTagText();data+=bs+fc+'tags'+fe;data+=tagText+rn;var section=$("section");if(section){data+=bs+fc+'section'+fe;data+=section.value+rn;}
var schedTime=$("scheduleTime");if(schedTime&&schedTime.value){data+=bs+fc+'scheduleTime'+fe;data+=schedTime.value+rn;}
var schedDate=$("scheduleDate");if(schedDate&&schedDate.value){data+=bs+fc+'scheduleDate'+fe;data+=schedDate.value+rn;}
var reallySched=$("reallySched");if(reallySched&&reallySched.checked){data+=bs+fc+'reallySched'+fe;data+=reallySched.checked+rn;}
var hasPoll=false;var pollForm=kos.getChildByTagName(kst.pollDiv,"form");if(pollForm){var pollQueryInput=$("piq");if(pollQueryInput&&pollQueryInput.value.length<1){hasPoll=false;}else if(pollQueryInput){for(var i=1;i<=kst.MAX_POLL_OPTIONS;++i){var pin=$("pi"+i);if(pin&&pin.value.length>0){hasPoll=true;}}
if(hasPoll){var qid=kos.getElementsByName(kst.pollDiv,"qid","input")[0];data+=bs+fc+'qid'+fe;data+=qid.value+rn;data+=bs+fc+'question'+fe;data+=pollQueryInput.value+rn;var aid=1;for(i=1;i<=kst.MAX_POLL_OPTIONS;++i){pin=$("pi"+i);if(pin&&pin.value.length>0){data+=bs+fc+'answer'+aid+fe;data+=pin.value+rn;++aid;}}}}}
data+=bs+"--"+rn;return data;},parseErrorReport:function(errMsg,divId){var divText='<div id="'+divId+'">';var divIndex=errMsg.indexOf(divText);if(divIndex<0){log("no errors for "+divId+".");return null;}
divIndex=divIndex+divText.length;var divContent=errMsg.substring(divIndex,errMsg.indexOf("</div>",divIndex));log("errors for "+divId+":"+divContent);return divContent;},finishPublish:function(kjaxReq){this.input.disabled=false;if(kjaxReq.FAILED){kos.removeBusyBall(this.bbs,false);return false;}
var titleErrors=$("titleErrors");if(titleErrors){titleErrors.parentNode.removeChild(titleErrors);}
var introErrors=$("introErrors");if(introErrors){introErrors.parentNode.removeChild(introErrors);}
var bodyErrors=$("bodyErrors");if(bodyErrors){bodyErrors.parentNode.removeChild(bodyErrors);}
var pollErrors=$("pollErrors");if(pollErrors){pollErrors.parentNode.removeChild(pollErrors);}
var tagErrors=$("tagErrors");if(tagErrors){tagErrors.parentNode.removeChild(tagErrors);}
var errMsg=kjaxReq.xhr.responseText;if(errMsg.indexOf("error")>-1){log("submission errors found!");kos.removeBusyBall(this.bbs,false);kst.setupForEditing();kos.mainDiv.className="editing";var titleErrorsText=kst.parseErrorReport(errMsg,"titleErrors");var titleErrorMessage=$("titleErrorMessage");if(titleErrorsText&&titleErrorMessage){titleErrors=$("titleErrors");if(!titleErrors){titleErrors=document.createElement("div");titleErrors.id="titleErrors";}
titleErrors.innerHTML=titleErrorsText;kos.insertAfter(titleErrors,titleErrorMessage);kos.setDisplayStyle($("titleErrors"),kos.DISPLAY_BLOCK,null,true);$("titleInput").focus();}
var introErrorsText=kst.parseErrorReport(errMsg,"introErrors");var ieErrorMessage=$("ieErrorMessage");if(introErrorsText&&ieErrorMessage){introErrors=$("introErrors");if(!introErrors){introErrors=document.createElement("div");introErrors.id="introErrors";}
introErrors.innerHTML=introErrorsText;kos.insertAfter(introErrors,ieErrorMessage);kos.setDisplayStyle($("introErrors"),kos.DISPLAY_BLOCK,null,true);$("ieText").focus();}
var bodyErrorsText=kst.parseErrorReport(errMsg,"bodyErrors");var beText=$("beText");if(bodyErrorsText&&beText){bodyErrors=$("bodyErrors");if(!bodyErrors){bodyErrors=document.createElement("div");bodyErrors.id="bodyErrors";}
bodyErrors.innerHTML=bodyErrorsText;log("There are bodyErrors");beText.parentNode.parentNode.insertBefore(bodyErrors,beText.parentNode);kos.setDisplayStyle($("bodyErrors"),kos.DISPLAY_BLOCK,null,true);beText.focus();}
var pollErrorsText=kst.parseErrorReport(errMsg,"pollErrors");var pollErrorMessage=$("pollErrorMessage");if(pollErrorsText&&pollErrorMessage){pollErrors=$("pollErrors");if(!pollErrors){pollErrors=document.createElement("div");pollErrors.id="pollErrors";}
pollErrors.innerHTML=pollErrorsText;kos.insertAfter(pollErrors,pollErrorMessage);kos.setDisplayStyle($("pollErrors"),kos.DISPLAY_BLOCK,null,true);}
var tagErrorsText=kst.parseErrorReport(errMsg,"tagErrors");var tagErrorMessage=$("tagErrorMessage");if(tagErrorsText&&tagErrorMessage){tagErrors=$("tagErrors");if(!tagErrors){tagErrors=document.createElement("div");tagErrors.id="tagErrors";}
tagErrors.innerHTML=tagErrorsText;kos.insertAfter(tagErrors,tagErrorMessage);kos.setDisplayStyle($("tagErrors"),kos.DISPLAY_BLOCK,null,true);$("tagInput").focus();}
if(errMsg.indexOf("postingLimit")!=-1){alert("You have already published as many diaries as you are allowed for today."+"\nA draft of this diary has been saved to your Drafts menu. You may publish it tomorrow.");}else{var errTxt = kst.parseErrorReport(errMsg,"pubErr");alert(document.title+":\nThere was an error publishing your Diary.\n\n"+errTxt);}
return false;}
if(errMsg.indexOf('<p>OK</p>')==-1){var errTxt = kst.parseErrorReport(errMsg,"pubErr");alert(document.title+":\nThere was an error publishing your Diary.\n\n"+errTxt);kos.removeBusyBall(this.bbs,false);return false;}
var reloadThePage=false;if(errMsg.indexOf('id="reload"')>-1){reloadThePage=true;}
kos.removeBusyBall(this.bbs,true);kos.mainDiv.className="published";var wasPublishedBefore=kst.hasBeenPublished;kst.hasBeenPublished=true;var titleText=kos.makeHighBitHtmlEntities($("titleInput").value);document.title=kst.SITE_TITLE+titleText;var diaryDraftsUl=$("diaryDrafts");if(diaryDraftsUl){var storySid=kos.STORY_BASE+kos.sid;var diaryDrafts=kos.getChildrenByTagName(diaryDraftsUl,"li");for(var d=0;d<diaryDrafts.length;++d){var draftA=kos.getChildByTagName(diaryDrafts[d],"a");if(draftA){var draftHref=draftA.getAttribute("href");if(!draftHref){draftHref=draftA.href;}
if(draftHref&&(draftHref.length>storySid.length)){draftHref=draftHref.substring(draftHref.length-storySid.length);}
if(draftHref==storySid){log("updated draft menu");draftA.style.display=kos.DISPLAY_NONE;if(diaryDrafts.length==1){var noDraftsP=$("noDiaryDrafts");if(noDraftsP){noDraftsP.style.display=kos.DISPLAY_BLOCK;}}
break;}}}}
var hasPoll=false;var pollForm=kos.getChildByTagName(kst.pollDiv,"form");if(pollForm){var pollQueryInput=$("piq");if(pollQueryInput&&pollQueryInput.value.length<1){hasPoll=false;}else if(pollQueryInput){for(var i=1;i<=kst.MAX_POLL_OPTIONS;++i){var pin=$("pi"+i);if(pin&&pin.value.length>0){hasPoll=true;}}
if(hasPoll){for(i=1;i<=kst.MAX_POLL_OPTIONS;++i){pin=$("pi"+i);if(pin&&pin.value.length<1){pin.parentNode.parentNode.parentNode.removeChild(pin.parentNode.parentNode);var prn=$("pr"+i+"_"+kst.pollDiv.id);if(prn){prn.parentNode.removeChild(prn);}}}
pollQueryInput.parentNode.removeChild(pollQueryInput);}}}
var tagSubmit=$("tagSubmit");if(tagSubmit){tagSubmit.style.display=kos.DISPLAY_INLINE;}
var pollSubmit=kos.getElementByClassName(kst.pollDiv,"pollSubmit","input");if(pollSubmit){pollSubmit.onclick=kos.submitPoll;pollSubmit.disabled=true;}
var postBot=$("postBot");if(postBot){postBot.disabled=false;postBot.style.opacity="1";postBot.onclick=kos.setupEditorDiary;}
var postAComment=$("postAComment");if(postAComment){postAComment.disabled=false;postAComment.style.opacity="1";postAComment.onclick=kos.setupEditorDiary;}
kst.submittedUpdate=true;window.scrollTo(0,0);if(reloadThePage){setTimeout(kos.reloadPage,30);alert(document.title+":\nThis diary has now been published. \n\nPlease wait while the page is reloaded...");}else{setTimeout(kos.refreshContentNow,30);alert(document.title+":\nThis diary has now been published.");}
return false;},rewireStory:function(){kst.submittedUpdate=false;var authorid=$("authorid");if(authorid){kst.authorId=authorid.value;}
kst.entryDiv=kos.getChildByClassName($("story"),"entry");if(!kst.entryDiv){log("no entry div in story!");return false;}
kst.introDiv=kos.getElementByClassName(kst.entryDiv,"intro","div");kst.pollDiv=kos.getElementByClassName(kos.mainDiv,"poll","div");kst.introEditor=$("ie");if(kst.introEditor){log("Rewiring intro editor...");kst.introEditor.editorPrefix="ie";kos.rewireEditor("ie");}
kst.bodyEditor=$("be");if(kst.bodyEditor){log("Rewiring body editor...");kst.bodyEditor.editorPrefix="be";kos.rewireEditor("be");}
var previewButton=$("previewButton");if(previewButton){previewButton.onclick=kst.previewDiary;}
var publishButton=$("publishButton");if(publishButton){publishButton.onclick=kst.publishDiary;}
var draftButton=$("draftButton");if(draftButton){if(kst.authorId==kos.uid||kst.inq){draftButton.onclick=kst.saveAsDraft;}else{draftButton.onclick=kos.returnFalse;draftButton.disabled=true;}}
var movQueueButton=$("movQueueButton");if(movQueueButton){if(kst.queueable){movQueueButton.onclick=kst.movQueue;}else{if(!kst.inq){/* movQueueButton.onclick=kos.returnFalse; */movQueueButton.onclick=kst.movQueue;}else{movQueueButton.onclick=kst.movQueue;}movQueueButton.disabled=(!kst.inq)?true:false;var movqb=(kst.inq)?"Remove From Queue":"Published";movQueueButton.value=movqb;}}
var editDiaryButton=$("editDiaryButton");if(editDiaryButton){editDiaryButton.onclick=kst.editDiary;}
var editLinks=kos.getElementsByClassName(kos.mainDiv,"editDiary","a");for(var i=0;i<editLinks.length;++i){editLinks[i].onclick=kst.editDiary;}
var deleteDiaryButton=$("deleteDiaryButton");if(deleteDiaryButton){deleteDiaryButton.onclick=kst.confirmDelete;}
var addPoll=$("addPoll");if(addPoll){addPoll.onclick=kst.addPoll;}
var rmvPoll=$("rmvPoll");if(rmvPoll){rmvPoll.onclick=kst.removePoll;}
var pollSubmit=kos.getElementByClassName(kst.pollDiv,"pollSubmit","input");if(pollSubmit){pollSubmit.onclick=kos.returnFalse;}
if(kos.mainDiv.className.indexOf("newdiary")>-1){log("new diary being edited.");var postBot=$("postBot");if(postBot){postBot.disabled=true;postBot.style.opacity="0.5";postBot.onclick=kos.returnFalse;}
var postAComment=$("postAComment");if(postAComment){postAComment.disabled=true;postAComment.style.opacity="0.5";postAComment.onclick=kos.returnFalse;}}
if(kos.mainDiv.className.indexOf("editing")>-1){kst.setupForEditing();var intro=kst.introDiv;var extended=$("extended");extended.disabled=intro.disabled=true;if(kos.isIE6Minus){extended.style.filter=intro.style.filter="alpha(opacity=40)";}
extended.style.opacity=intro.style.opacity=0.4;var titleInput=$("titleInput");if(titleInput){titleInput.focus();titleInput.select();}
window.scrollTo(0,0);}
return true;}};
