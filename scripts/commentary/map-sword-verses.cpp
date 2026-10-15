// Build-time audit helper using the official SWORD API. Never linked into the app.
#include <swmgr.h>
#include <swmodule.h>
#include <versekey.h>
#include <CommonCrypto/CommonDigest.h>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <string>
#include <cctype>
std::string quoted(const std::string &s){std::string o="\"";for(unsigned char c:s){if(c=='"'||c=='\\'){o+='\\';o+=c;}else if(c<32){char b[7];snprintf(b,7,"\\u%04x",c);o+=b;}else o+=c;}return o+'"';}
int main(int argc,char**argv){if(argc!=3)return 2;sword::SWMgr manager(argv[1],true,nullptr,false,false);auto module=manager.getModule(argv[2]);if(!module)return 3;std::string line;while(std::getline(std::cin,line)){auto cut=line.find('\t');if(cut==std::string::npos)return 4;auto ref=line.substr(0,cut),query=line.substr(cut+1);module->setKey(query.c_str());auto key=dynamic_cast<sword::VerseKey*>(module->getKey());if(!key||module->popError())return 5;auto &buf=module->getRawEntryBuf();std::string body(buf.c_str(),buf.size());if(module->popError())return 6;while(!body.empty()&&std::isspace((unsigned char)body.back()))body.pop_back();size_t start=0;while(start<body.size()&&std::isspace((unsigned char)body[start]))start++;body=body.substr(start);unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(body.data(),(CC_LONG)body.size(),digest);std::ostringstream hash;for(auto b:digest)hash<<std::hex<<std::setw(2)<<std::setfill('0')<<(int)b;std::cout<<"{\"ref\":"<<quoted(ref)<<",\"actualBook\":"<<quoted(key->getBookName())<<",\"chapter\":"<<key->getChapter()<<",\"verse\":"<<key->getVerse()<<",\"bytes\":"<<body.size()<<",\"sha256\":"<<quoted(hash.str())<<"}\n";}return 0;}
