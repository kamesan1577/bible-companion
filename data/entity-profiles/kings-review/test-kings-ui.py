from pathlib import Path
import subprocess
N=Path(__file__).resolve().parent;C=N/'candidate/apps/ios'
args=['/usr/bin/xcodebuild','-project',str(C/'BibleCompanion.xcodeproj'),'-scheme','ReadingInteractionUI','-destination','platform=iOS Simulator,id=AD7F4829-D6EE-4970-A600-9B10CD99CA53','-derivedDataPath',str(N/'DerivedData'),' -resultBundlePath'.strip(),str(N/'KingsUIFinal.xcresult'),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','BIBLE_BUNDLE_ID=org.kamesan1577.BibleCompanion','BIBLE_APP_GROUP=group.org.kamesan1577.BibleCompanion','-only-testing:ReadingInteractionUITests/KingsEntityUITests','test']
with (N/'kings-ui-test.log').open('w')as out:r=subprocess.run(args,cwd=C,stdout=out,stderr=subprocess.STDOUT)
print('Targeted context runtime test exit',r.returncode);raise SystemExit(r.returncode)
